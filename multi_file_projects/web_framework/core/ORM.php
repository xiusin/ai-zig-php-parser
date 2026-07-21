<?php
// ORM ActiveRecord 模式
abstract class Model {
    protected string $table;
    protected array $fillable = [];
    protected array $hidden = [];
    protected array $attributes = [];
    protected array $casts = [];
    protected bool $exists = false;

    public function __construct(array $attributes = []) {
        $this->fill($attributes);
    }

    public function fill(array $attributes): self {
        foreach ($attributes as $key => $value) {
            if (in_array($key, $this->fillable) || empty($this->fillable)) {
                $this->attributes[$key] = $value;
            }
        }
        return $this;
    }

    public function forceFill(array $attributes): self {
        foreach ($attributes as $key => $value) {
            $this->attributes[$key] = $value;
        }
        return $this;
    }

    public function __get(string $name): mixed {
        if (array_key_exists($name, $this->attributes)) {
            return $this->castAttribute($name, $this->attributes[$name]);
        }
        return null;
    }

    public function __set(string $name, mixed $value): void {
        $this->attributes[$name] = $value;
    }

    public function __isset(string $name): bool {
        return isset($this->attributes[$name]);
    }

    private function castAttribute(string $name, mixed $value): mixed {
        $cast = $this->casts[$name] ?? null;
        if ($cast === null || $value === null) return $value;
        return match($cast) {
            'int', 'integer' => (int)$value,
            'float', 'double' => (float)$value,
            'string' => (string)$value,
            'bool', 'boolean' => (bool)$value,
            'array' => is_array($value) ? $value : json_decode($value, true),
            'json' => json_decode($value, true),
            default => $value,
        };
    }

    public function save(): bool {
        $db = Database::getInstance();
        if ($this->exists) {
            $id = $this->attributes['id'] ?? null;
            if ($id !== null) {
                $db->table($this->table)->where('id', $id)->update($this->attributes);
                return true;
            }
        } else {
            $data = array_filter($this->attributes, fn($k) => $k !== 'id', ARRAY_FILTER_USE_KEY);
            $id = $db->table($this->table)->insert($data);
            $this->attributes['id'] = $id;
            $this->exists = true;
            return true;
        }
        return false;
    }

    public function delete(): bool {
        $db = Database::getInstance();
        $id = $this->attributes['id'] ?? null;
        if ($id !== null) {
            $db->table($this->table)->where('id', $id)->delete();
            $this->exists = false;
            return true;
        }
        return false;
    }

    public static function find(int $id): ?static {
        $instance = new static();
        $db = Database::getInstance();
        $row = $db->table($instance->table)->where('id', $id)->first();
        if ($row) {
            $model = new static();
            $model->forceFill($row);
            $model->exists = true;
            return $model;
        }
        return null;
    }

    public static function all(): array {
        $instance = new static();
        $db = Database::getInstance();
        $rows = $db->table($instance->table)->get();
        $models = [];
        foreach ($rows as $row) {
            $model = new static();
            $model->forceFill($row);
            $model->exists = true;
            $models[] = $model;
        }
        return $models;
    }

    public static function where(string $column, mixed $operator, mixed $value = null): QueryBuilder {
        $instance = new static();
        $db = Database::getInstance();
        $qb = $db->table($instance->table);
        return $qb->where($column, $operator, $value);
    }

    public function toArray(): array {
        $result = [];
        foreach ($this->attributes as $key => $value) {
            if (!in_array($key, $this->hidden)) {
                $result[$key] = $this->castAttribute($key, $value);
            }
        }
        return $result;
    }

    public function toJson(): string {
        return json_encode($this->toArray());
    }
}
