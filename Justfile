# Build one example.
# If the example has its own Justfile, delegate to its `build` recipe
# (which may do custom setup e.g. secrets). Otherwise run podman build.
build example:
    #!/bin/bash
    set -euo pipefail
    if [ -f "{{example}}/Justfile" ]; then
        just --justfile "{{example}}/Justfile" --working-directory "{{example}}" build
    else
        podman build -t "localhost/{{example}}:latest" "{{example}}"
    fi

# Build every example that contains a Containerfile.
build-all:
    #!/bin/bash
    set -euo pipefail
    for d in */; do
        [ -f "$d/Containerfile" ] || continue
        just build "${d%/}"
    done
