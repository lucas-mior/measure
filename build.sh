#!/bin/sh

# shellcheck disable=SC2086

set -e

error () {
    >&2 printf "$@"
    return
}

if [ -n "$BASH_VERSION" ]; then
    # shellcheck disable=SC3044
    shopt -s expand_aliases
fi

# gtk might not work correctly if you have stuff here
export XDG_DATA_DIRS=""

alias trace_on='set -x'
alias trace_off='{ set +x; } 2>/dev/null'

# export LC_ALL=C

dir=$(dirname "$(readlink -f "$0")")
CPPFLAGS="$CPPFLAGS -I$dir/cbase"
CPPFLAGS="$CPPFLAGS -I."

cd "$dir" || exit
program=$(basename "$(readlink -f "$(dirname "$0")")")
script=$(basename "$0")

if [ -f ./targets ]; then
    . ./targets
else
    targets=$(cat <<'EOF_TARGETS'
build
debug
fast_feedback
install
uninstall
test
check
release
run
cross x86_64-linux
cross aarch64-linux
cross x86_64-macos
cross aarch64-macos
cross x86_64-windows-gnu
EOF_TARGETS
)
fi

target="${1:-debug}"
target_line=$target
if [ "$target" = "cross" ] && [ -n "${2:-}" ]; then
    target_line="$target $2"
fi

target_supported () {
    wanted=$1
    printf '%s\n' "$targets" | awk -v wanted="$wanted" '
        {
            line = $0
            sub(/^# /, "", line)
        }
        line == wanted { found = 1 }
        END { exit !found }
    '
}

if ! target_supported "$target_line" && ! target_supported "$target"; then
    echo "usage: $script <targets>"
    printf '%s\n' "$targets"
    exit 1
fi

printf "\n${script} ${RED}${1} ${2}$RES\n"

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-/}"

main="main.c"
exe="bin/$program"
mkdir -p "$(dirname "$exe")"

CPPFLAGS="$CPPFLAGS -D_DEFAULT_SOURCE"
CPPFLAGS="$CPPFLAGS -DGETTEXT_PACKAGE=$program"
CPPFLAGS="$CPPFLAGS -DLOCALEDIR=$PREFIX/share/locale"

CFLAGS="$CFLAGS -std=c11"
CFLAGS="$CFLAGS -Wfatal-errors"
CFLAGS="$CFLAGS -Wall -Wextra"
# CFLAGS="$CFLAGS -Werror"
CFLAGS="$CFLAGS -Wno-format-pedantic"
CFLAGS="$CFLAGS -Wno-unknown-warning-option"
CFLAGS="$CFLAGS -Wno-gnu-union-cast"
CFLAGS="$CFLAGS -Wno-unused-macros"
CFLAGS="$CFLAGS -Wno-constant-logical-operand"
CFLAGS="$CFLAGS -Wno-float-equal"
CFLAGS="$CFLAGS -Wno-cast-qual"
CFLAGS="$CFLAGS -Wno-deprecated-declarations"
CFLAGS="$CFLAGS -Wno-unknown-pragmas"
CFLAGS="$CFLAGS -Wno-format-security"

LDFLAGS="$LDFLAGS -lm"
OS=$(uname -a)

case "$target" in
debug|test)
    CC="${CC:-tcc}"
    ;;
fast_feedback)
    CC="${CC:-clang}"
    ;;
*)
    CC="${CC:-cc}"
    ;;
esac

if echo "$OS" | grep -q "Linux"; then
    if echo "$OS" | grep -q "GNU"; then
        GNUSOURCE="-D_GNU_SOURCE"
    fi
fi

option_remove() {
    echo "$1" | sed -E "s| *$2 +| |g"
}

compile_with_chibicc () {
    args="$*"
    while ! problem=$(chibicc $args 2>&1); do
        trace_off
        sleep 0.4
        if echo "$problem" | grep -q "unknown argument:"; then
            arg=$(echo "$problem" | awk '{print $NF}')
            printf "\nRemoving argument $arg...\n"
            args=$(option_remove "$args" "$arg")
        elif echo "$problem" | grep -q "unknown file extension:"; then
            arg=$(echo "$problem" | awk '{print $NF}')
            printf "\nRemoving argument $arg...\n"
            args=$(option_remove "$args" "$arg")
        else
            printf "\n\nError compiling with chibicc:\n\n${problem}\n\n"
            return 1
        fi
        printf "\n"
        trace_on
    done
    return 0
}

case "$target" in
debug)
    CFLAGS="$CFLAGS -g3 -fsanitize=undefined"
    CPPFLAGS="$CPPFLAGS $GNUSOURCE -DDEBUGGING=1"
    exe="bin/${program}_debug"
    ;;
test)
    CFLAGS="$CFLAGS -g $GNUSOURCE -DDEBUGGING=1 -fsanitize=undefined"
    ;;
check)
    CC=gcc
    CFLAGS="$CFLAGS $GNUSOURCE -DDEBUGGING=1 -fanalyzer"
    ;;
"build"|"run")
    CFLAGS="$CFLAGS $GNUSOURCE -O2 -flto -march=native -ftree-vectorize"
    ;;
release)
    CFLAGS="$CFLAGS $GNUSOURCE -DRELEASING=1 -O2 -flto -march=native -ftree-vectorize"
    ;;
fast_feedback)
    CFLAGS="$CFLAGS $GNUSOURCE -Werror"
    ;;
*)
    CFLAGS="$CFLAGS -O2"
    ;;
esac

if [ "$target" = "cross" ]; then
    cross="$2"
    CC="zig cc"
    CFLAGS="$CFLAGS -target $cross"
    CFLAGS=$(option_remove "$CFLAGS" "-D_GNU_SOURCE")

    case $cross in
    "x86_64-macos"|"aarch64-macos")
        CFLAGS="$CFLAGS -fno-lto"
        LDFLAGS="$LDFLAGS -lpthread"
        ;;
    *windows*)
        exe="bin/$program.exe"
        ;;
    *)
        LDFLAGS="$LDFLAGS -lpthread"
        ;;
    esac
else
    LDFLAGS="$LDFLAGS -lpthread"
fi

if [ "$CC" = "clang" ]; then
    CFLAGS="$CFLAGS -Weverything"
    CFLAGS="$CFLAGS -Wno-pedantic"
    CFLAGS="$CFLAGS -Wno-unsafe-buffer-usage"
    CFLAGS="$CFLAGS -Wno-format-nonliteral"
    CFLAGS="$CFLAGS -Wno-disabled-macro-expansion"
    CFLAGS="$CFLAGS -Wno-c++-keyword"
    CFLAGS="$CFLAGS -Wno-pre-c11-compat"
    CFLAGS="$CFLAGS -Wno-implicit-void-ptr-cast"
    CFLAGS="$CFLAGS -Wno-implicit-int-enum-cast"
    CFLAGS="$CFLAGS -Wno-covered-switch-default"
    CFLAGS="$CFLAGS -Wno-reserved-identifier"  # because of __GTK_H_INSIDE__
    CFLAGS="$CFLAGS -Wno-documentation"
    CFLAGS="$CFLAGS -Wno-documentation-unknown-command"
    CFLAGS="$CFLAGS -Wno-padded"
    CFLAGS="$CFLAGS -Wno-cast-function-type-strict"
    CFLAGS="$CFLAGS -Wno-assign-enum"
    CFLAGS="$CFLAGS -Wno-used-but-marked-unused"
    CFLAGS="$CFLAGS -Wno-double-promotion"
    CFLAGS="$CFLAGS -Wno-cast-function-type-strict"

    # to avoid using -Wno-unused-function
    CFLAGS="$CFLAGS -Wno-unneeded-internal-declaration"

    # only for the LSP. It does not understand unity builds
    CFLAGS="$CFLAGS -Wno-undefined-internal"
fi

case "$target" in
fast_feedback)
    trace_on
    $CC $CPPFLAGS $CFLAGS main.c -o "$exe" $LDFLAGS
    trace_off
    ;;
build|debug|run|release)
    trace_on

    ctags --kinds-C=+l+d cbase/*.c *.h src/*.c  2> /dev/null || true
    vtags.sed tags | sort | uniq > .tags.vim 2> /dev/null || true
    if [ "$CC" = "chibicc" ]; then
        compile_with_chibicc $CPPFLAGS $CFLAGS main.c -o $exe $LDFLAGS
    else
        $CC $CPPFLAGS $CFLAGS main.c -o "$exe" $LDFLAGS
    fi

    if [ $target = "run" ]; then
        $exe $2
    fi

    trace_off
    ;;
install)
    trace_on
    $0 release
    install -Dm755 bin/${program}   ${DESTDIR}${PREFIX}/bin/${program}
    install -Dm644 ${program}.1     ${DESTDIR}${PREFIX}/man/man1/${program}.1

    if [ -d "etc" ]; then
        install -dm755 "$DESTDIR/etc/$program"
        cp -rp etc/* "$DESTDIR/etc/$program/"
    fi
    if [ -f "$program.desktop" ]; then
        install -Dm755 \
            "$program.desktop" \
            "$DESTDIR/usr/share/applications/$program.desktop"
    fi
    trace_off
    exit
    ;;
test)
    find . -iname "*.c" | sort | while read -r src; do
        trace_off
        name=$(basename "$src")

        if [ -n "$2" ] && [ "$name" != "$2" ]; then
            continue
        fi
        if [ "$name" = "$main" ]; then
            continue
        fi
        if echo "$src" | grep -q "stc/"; then
            continue
        fi
        name=$(echo "$name" | sed 's/\.c//')
        test_exe="/tmp/${name}_test"

        printf "\nTesting ${RED}${src}${RES} ...\n"

        flags="$(awk '/\/\/ flags:/ { $1=$2=""; print $0 }' "$src")"
        if [ $src = "gwindows_functions.c" ]; then
            if ! zig version; then
                continue
            fi
            cmdline="zig cc $CPPFLAGS $CFLAGS"
            cmdline=$(option_remove "$cmdline" "-D_GNU_SOURCE")
            cmdline="$cmdline -target x86_64-windows-gnu"
            cmdline="$cmdline -Wno-unused-variable -DTESTING_$name=1 -DTESTING=1"
            cmdline="$cmdline $flags -o $test_exe $src"
        else
            cmdline="$CC $CPPFLAGS $CFLAGS"
            cmdline="$cmdline -Wno-unused-variable -DTESTING_$name=1 -DTESTING=1 $LDFLAGS"
            cmdline="$cmdline $flags -o $test_exe $src"
        fi

        if [ "$CC" = "chibicc" ]; then
            cmdline_no_cc=$(option_remove "$cmdline" "$CC")
            trace_on
            if compile_with_chibicc "$cmdline_no_cc"; then
                /tmp/${name}_test
            else
                exit 1
            fi
        else
            trace_on
            if $cmdline; then
                $test_exe || gdb $test_exe -ex run
            else
                exit
            fi
        fi
        trace_off
    done
    exit
    ;;
uninstall)
    rm -vf  "${DESTDIR}${PREFIX}/bin/${program:?}"
    rm -vf  "${DESTDIR}${PREFIX}/man/man1/${program:?}.1"
    rm -rvf "$DESTDIR/etc/${program:?}/"
    rm -vf  "$DESTDIR/usr/share/applications/${program:?}.desktop"
    exit
    ;;
esac

case "$target" in
check)
    CC=gcc CFLAGS="-fanalyzer" ./build.sh

    CFLAGS="--analyze -Xanalyzer -analyzer-output=text"
    CFLAGS="$CFLAGS -Xanalyzer -analyzer-werror"
    CFLAGS="$CFLAGS -Xanalyzer -analyzer-opt-analyze-headers"
    CFLAGS="$CFLAGS -Wno-unused-command-line-argument"
    CC=clang CFLAGS="$CFLAGS" ./build.sh
    exit
    ;;
esac
