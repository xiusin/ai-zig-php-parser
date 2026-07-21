<?php
// 首页控制器
class HomeController extends Controller {
    public function index(Request $request): Response {
        $items = ['Welcome', 'Features', 'Docs', 'API', 'Community'];
        return $this->json([
            'message' => 'Welcome to Web Framework',
            'version' => '1.0.0',
            'items' => $items,
            'count' => count($items),
            'request_path' => $request->path,
        ]);
    }

    public function health(): Response {
        return $this->json([
            'status' => 'ok',
            'timestamp' => date('Y-m-d H:i:s'),
            'database' => 'connected',
            'session' => 'active',
        ]);
    }

    public function renderHome(Request $request): Response {
        $items = ['Item A', 'Item B', 'Item C', 'Item D'];
        return $this->view('home', ['title' => 'Welcome Page', 'items' => $items]);
    }
}

// 用户控制器
class UserController extends Controller {
    public function index(Request $request): Response {
        $users = User::all();
        $data = [];
        foreach ($users as $user) {
            $data[] = $user->toArray();
        }
        return $this->json(['users' => $data, 'total' => count($data)]);
    }

    public function show(Request $request): Response {
        $id = (int)($request->param('id') ?? 0);
        $user = User::find($id);
        if (!$user) {
            throw new NotFoundException('User not found');
        }
        return $this->json(['user' => $user->toArray()]);
    }

    public function create(Request $request): Response {
        $validated = $this->validate($request, [
            'name' => 'required|string|max:100',
            'email' => 'required|email',
            'password' => 'required|min:6',
            'role' => 'in:admin,user,guest',
        ]);
        if (User::findByEmail($validated['email'])) {
            throw new BadRequestException('Email already exists');
        }
        $user = new User([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => User::hashPassword($validated['password']),
            'role' => $validated['role'] ?? 'user',
            'status' => 'active',
        ]);
        $user->save();
        return $this->json(['user' => $user->toArray()], 201);
    }

    public function update(Request $request): Response {
        $id = (int)($request->param('id') ?? 0);
        $user = User::find($id);
        if (!$user) {
            throw new NotFoundException('User not found');
        }
        $validated = $this->validate($request, [
            'name' => 'string|max:100',
            'role' => 'in:admin,user,guest',
            'status' => 'in:active,inactive,banned',
        ]);
        foreach ($validated as $key => $value) {
            $user->$key = $value;
        }
        $user->save();
        return $this->json(['user' => $user->toArray()]);
    }

    public function destroy(Request $request): Response {
        $id = (int)($request->param('id') ?? 0);
        $user = User::find($id);
        if (!$user) {
            throw new NotFoundException('User not found');
        }
        $user->delete();
        return $this->json(['deleted' => true, 'id' => $id]);
    }

    public function login(Request $request): Response {
        $validated = $this->validate($request, [
            'email' => 'required|email',
            'password' => 'required',
        ]);
        $user = User::findByEmail($validated['email']);
        if (!$user || !$user->verifyPassword($validated['password'])) {
            throw new UnauthorizedException('Invalid credentials');
        }
        if (!$user->isActive()) {
            throw new ForbiddenException('Account is not active');
        }
        $session = Session::getInstance();
        $token = $session->createToken($user->id);
        return $this->json([
            'token' => $token,
            'user' => $user->toArray(),
        ]);
    }

    public function profile(Request $request): Response {
        $userId = $request->param('auth_user_id');
        $user = User::find($userId);
        if (!$user) {
            throw new NotFoundException('User not found');
        }
        $posts = $user->posts();
        $postCount = count($posts);
        return $this->json([
            'user' => $user->toArray(),
            'posts_count' => $postCount,
        ]);
    }
}

// 文章控制器
class PostController extends Controller {
    public function index(Request $request): Response {
        $page = (int)($request->query('page', 1));
        $perPage = (int)($request->query('per_page', 10));
        $offset = ($page - 1) * $perPage;

        $qb = Post::where('status', 'published');
        $total = $qb->count();
        $posts = $qb->orderBy('id', 'DESC')->limit($perPage)->offset($offset)->get();

        $data = [];
        foreach ($posts as $post) {
            $model = new Post($post);
            $model->exists = true;
            $data[] = [
                'id' => $model->id,
                'title' => $model->title,
                'excerpt' => $model->excerpt(50),
                'author' => $model->author()?->name,
                'views' => $model->views,
            ];
        }
        return $this->json([
            'posts' => $data,
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
            'total_pages' => ceil($total / $perPage),
        ]);
    }

    public function show(Request $request): Response {
        $id = (int)($request->param('id') ?? 0);
        $post = Post::find($id);
        if (!$post || !$post->isPublished()) {
            throw new NotFoundException('Post not found');
        }
        $post->incrementViews();
        $author = $post->author();
        $comments = $post->comments();
        return $this->json([
            'post' => $post->toArray(),
            'author' => $author?->toArray(),
            'comments_count' => count($comments),
        ]);
    }

    public function store(Request $request): Response {
        $userId = $request->param('auth_user_id');
        $validated = $this->validate($request, [
            'title' => 'required|string|max:200',
            'content' => 'required|string',
        ]);
        $post = new Post([
            'title' => $validated['title'],
            'content' => $validated['content'],
            'user_id' => $userId,
            'status' => 'published',
            'views' => 0,
        ]);
        $post->save();
        return $this->json(['post' => $post->toArray()], 201);
    }

    public function addComment(Request $request): Response {
        $postId = (int)($request->param('id') ?? 0);
        $userId = $request->param('auth_user_id');
        $post = Post::find($postId);
        if (!$post) {
            throw new NotFoundException('Post not found');
        }
        $validated = $this->validate($request, [
            'content' => 'required|string|max:500',
        ]);
        $comment = new Comment([
            'post_id' => $postId,
            'user_id' => $userId,
            'content' => $validated['content'],
            'status' => 'approved',
        ]);
        $comment->save();
        return $this->json(['comment' => $comment->toArray()], 201);
    }
}
