import re

with open('src/aot/native_linker.zig', 'r') as f:
    content = f.read()

lines = content.split('\n')
changes = 0
new_lines = []

for i, line in enumerate(lines):
    stripped = line.strip()
    
    # Check if this is an unconditional restore of return_generated
    if (re.match(r'^self\.return_generated = saved_\w+;', stripped) and
        not stripped.startswith('if (') and
        not stripped.startswith('defer')):
        indent = line[:len(line) - len(line.lstrip())]
        rest = stripped[len("self.return_generated = "):]
        new_line = f'{indent}if (!self.return_generated) self.return_generated = {rest}'
        new_lines.append(new_line)
        changes += 1
    # Check if this is an unconditional restore of break_generated  
    elif (re.match(r'^self\.break_generated = saved_\w+;', stripped) and
          not stripped.startswith('if (') and
          not stripped.startswith('defer')):
        indent = line[:len(line) - len(line.lstrip())]
        rest = stripped[len("self.break_generated = "):]
        new_line = f'{indent}if (!self.break_generated) self.break_generated = {rest}'
        new_lines.append(new_line)
        changes += 1
    else:
        new_lines.append(line)

with open('src/aot/native_linker.zig', 'w') as f:
    f.write('\n'.join(new_lines))

print(f'Changed {changes} unconditional restores to conditional')
