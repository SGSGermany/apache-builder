BASE_IMAGE="${BASE_IMAGE:-ghcr.io/sgsgermany/apache:latest}"
IMAGE="${IMAGE:-${CONFIG:-$(basename "$BASE_IMAGE" | cut -d ':' -f 1 | cut -d '@' -f 1)}}"
TAGS="${TAGS:-latest}"
[ -v ANNOTATIONS ] || ANNOTATIONS=()
