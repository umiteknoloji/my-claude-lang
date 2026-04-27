#!/usr/bin/env python3
"""Extract file-path tokens (including glob patterns) from a spec body.

Reads spec text from stdin or a file argument.
Outputs a JSON array of unique path strings.

Called by mcl-stop.sh on spec approval to populate scope_paths in state.json.
Called by mcl-pre-tool.sh to match Write/Edit targets against scope.

Extraction sources (in order of reliability):
  1. Backtick tokens:     `src/auth/login.ts`   `src/**/*.ts`
  2. Bold tokens:         **src/auth/login.ts**
  3. Bare path tokens:    any word-boundary token that looks like a file path

A token qualifies as a file path if ALL of:
  - contains at least one '/'
  - the final path segment has a known extension, is a known filename, or contains '*'
"""

import json, re, sys

# Extensions that identify something as a code/config file
_KNOWN_EXT = {
    'ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs', 'mts', 'cts',
    'py', 'pyi', 'pyx',
    'go',
    'rs',
    'java', 'kt', 'kts', 'groovy',
    'swift', 'objc', 'm',
    'c', 'cpp', 'cc', 'cxx', 'h', 'hpp', 'hxx',
    'cs', 'fs', 'fsx',
    'rb', 'erb',
    'php',
    'css', 'scss', 'sass', 'less', 'styl',
    'html', 'htm', 'xhtml', 'xml',
    'vue', 'svelte', 'astro',
    'json', 'jsonc', 'json5',
    'yaml', 'yml',
    'toml',
    'env', 'envrc',
    'md', 'mdx', 'rst', 'txt',
    'sh', 'bash', 'zsh', 'fish', 'ps1',
    'sql', 'prisma', 'graphql', 'gql',
    'tf', 'tfvars', 'hcl',
    'proto',
    'lock',
    'mod', 'sum',
    'gradle', 'xml', 'pom',
}

_KNOWN_FILENAMES = {
    'Dockerfile', 'Makefile', 'Procfile', 'Brewfile',
    'Gemfile', 'Rakefile', 'Guardfile',
    'CMakeLists.txt', 'BUILD', 'WORKSPACE',
    '.gitignore', '.gitattributes', '.gitmodules',
    '.eslintrc', '.prettierrc', '.babelrc', '.editorconfig',
    '.nvmrc', '.node-version', '.python-version', '.tool-versions',
}


def _is_path(token: str) -> bool:
    """True if token looks like a file/directory path or glob pattern."""
    t = token.strip('`\'"')
    if not t:
        return False
    # Must have at least one slash
    if '/' not in t and '*' not in t:
        return False
    # Reject URLs
    if t.startswith(('http://', 'https://', 'ftp://', '//')):
        return False
    # Get last segment
    last = t.rsplit('/', 1)[-1]
    # Known filename
    if last in _KNOWN_FILENAMES:
        return True
    # Glob pattern
    if '*' in t:
        return True
    # Known extension
    if '.' in last:
        ext = last.rsplit('.', 1)[-1].lower().rstrip(')')  # strip trailing paren from markdown
        if ext in _KNOWN_EXT:
            return True
    return False


def extract_paths(text: str) -> list[str]:
    found: set[str] = set()

    # 1. Backtick: `src/foo.ts`  `src/**/*.ts`
    for m in re.finditer(r'`([^`\n]+)`', text):
        s = m.group(1).strip()
        if _is_path(s):
            found.add(s)

    # 2. Bold: **src/foo.ts**
    for m in re.finditer(r'\*\*([^*\n]+)\*\*', text):
        s = m.group(1).strip()
        if _is_path(s):
            found.add(s)

    # 3. Bare tokens: word-boundary path-like strings
    # Capture tokens that start with a letter/digit/dot/underscore and contain slashes
    for m in re.finditer(
        r'(?<![:/\w@])([a-zA-Z_.][a-zA-Z0-9_.\-]*(?:/[a-zA-Z0-9_.\-*]+)+(?:/[a-zA-Z0-9_.\-*]*)?)',
        text,
    ):
        s = m.group(1).rstrip('.,;:)')
        if _is_path(s):
            found.add(s)

    # Normalise: strip leading ./ from each path
    result = []
    for p in found:
        p = p.lstrip('./')
        if p:
            result.append(p)

    return sorted(set(result))


if __name__ == '__main__':
    if len(sys.argv) > 1:
        try:
            with open(sys.argv[1], encoding='utf-8', errors='replace') as fh:
                text = fh.read()
        except OSError as e:
            print(f'mcl-spec-paths: cannot open {sys.argv[1]}: {e}', file=sys.stderr)
            sys.exit(1)
    else:
        text = sys.stdin.read()

    print(json.dumps(extract_paths(text)))
