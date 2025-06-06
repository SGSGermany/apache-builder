[ -v SITES ] || SITES=()
[ -v SITES_ALIASES ] || SITES_ALIASES=()
[ -v SITES_URLS ] || SITES_URLS=()

DEFAULT_SITE_MODE="${DEFAULT_SITE_MODE:-htdocs}"
DEFAULT_SITE_URL="${DEFAULT_SITE_URL:-}"
[[ "${DEFAULT_SITE_SSL:-}" =~ ^(1|y|yes|true)$ ]] \
    && DEFAULT_SITE_SSL="y" \
    || DEFAULT_SITE_SSL=""

HOST_HTDOCS_PATH_PATTERN="${HOST_HTDOCS_PATH_PATTERN:-/var/www/\$\{SITE\}}"
[ -v HOST_HTDOCS_PATHS ] || HOST_HTDOCS_PATHS=()

HOST_LOGS_PATH_PATTERN="${HOST_LOGS_PATH_PATTERN:-/var/log/apache2/\$\{SITE\}}"
[ -v HOST_LOGS_PATHS ] || HOST_LOGS_PATHS=()

HOST_SSL_PATH_PATTERN="${HOST_SSL_PATH_PATTERN:-/var/local/acme/live/\$\{SITE\}}"
[ -v HOST_SSL_PATHS ] || HOST_SSL_PATHS=()

HOST_PHP_FPM_PATH_PATTERN="${HOST_PHP_FPM_PATH_PATTERN:-/run/php-fpm/\$\{SITE\}}"
[ -v HOST_PHP_FPM_PATHS ] || HOST_PHP_FPM_PATHS=()

HOST_ACME_CHALLENGES_PATH="${HOST_ACME_CHALLENGES_PATH:-/var/local/acme/challenges}"

[ -v HOST_UID_MAP ] || HOST_UID_MAP=()
if ! grep -q '^apache2  ' < <(printf '%s\n' "${HOST_UID_MAP[@]}"); then
    if ! id -u -- "apache2" 2> /dev/null; then
        HOST_UID_MAP=( "apache2  $(id -u -- "$CONTAINER_USERNS")" "${HOST_UID_MAP[@]}" )
    fi
fi

[ -v HOST_GID_MAP ] || HOST_GID_MAP=()
if ! grep -q '^apache2  ' < <(printf '%s\n' "${HOST_GID_MAP[@]}"); then
    if ! id -g -- "apache2" 2> /dev/null; then
        HOST_GID_MAP=( "apache2  $(id -g -- "$CONTAINER_USERNS")" "${HOST_GID_MAP[@]}" )
    fi
fi

if [ ! -v APACHE_MODULES ]; then
    APACHE_MODULES=(
        # base modules
        "mpm_event"
        "authn_file"
        "authn_core"
        "authz_host"
        "authz_groupfile"
        "authz_user"
        "authz_core"
        "auth_basic"
        "reqtimeout"
        "mime"
        "log_config"
        "headers"
        "http2"
        "rewrite"
        "setenvif"
        "unixd"
        "autoindex"
        "dir"
        "alias"

        # additional base modules
        "ssl"
        "socache_shmcb"
        "proxy"
        "proxy_fcgi"
    )
fi

if [ ! -v APACHE_CONFIGS ]; then
    APACHE_CONFIGS=(
        # base configs
        "charset"
        "connection"
        "errors"
        "htaccess"
        "lookups"
        "security"
        "ssl"
        "ssl-ocsp-stapling"
        "ssl-security"

        # additional base configs
        "acme-challenge"
    )
fi
