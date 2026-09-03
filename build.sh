#!/bin/sh -e

# shellcheck disable=SC2086

dir=$(dirname "$(readlink -f "$0")")
cd "$dir" || exit

# shellcheck source=./cbase/common.sh
. "./cbase/common.sh"

# gtk might not work correctly if you have stuff here
export XDG_DATA_DIRS=""

# export LC_ALL=C

program=$(common_get_program "$0")
script=$(basename "$0")


common_build_parse_args "$@"

case "$mode" in
build|check|cross|debug|debug-fast|fast_feedback|install|release|run|test|uninstall)
    ;;
*)
    common_build_unknown_mode
    ;;
esac

common_build_print_invocation "$script"

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-/}"

exe="bin/$program"
mkdir -p "$(dirname "$exe")"

CC=$(common_get_compiler "$mode")

OS=$(uname -a)
if [ "$mode" = "cross" ] && [ "${target:-}" != "all" ]; then
    OS="$target"
fi

case "$OS" in
*MINGW*|*MSYS*|*CYGWIN*|*mingw*|*msys*|*cygwin*|*windows*)
    ;;
*)
    CFLAGS="$CFLAGS -pthread"
    ;;
esac

CPPFLAGS="$CPPFLAGS -I. -Icbase"
CPPFLAGS="$CPPFLAGS -DGETTEXT_PACKAGE=$program"
CPPFLAGS="$CPPFLAGS -DLOCALEDIR=$PREFIX/share/locale"

CFLAGS="$CFLAGS -std=c11"
CFLAGS="$CFLAGS -Wfatal-errors"

LDFLAGS="$LDFLAGS -lm"

case "$mode" in
debug)
    CFLAGS="$CFLAGS -g3"
    CPPFLAGS="$CPPFLAGS -DDEBUGGING=1"
    exe="bin/$program"
    ;;
debug-fast)
    CFLAGS="$CFLAGS -g2 -O2 -flto -march=native -ftree-vectorize"
    CFLAGS="$CFLAGS -fsanitize-trap=undefined"
    CPPFLAGS="$CPPFLAGS -DDEBUGGING=1"
    ;;
test)
    CFLAGS="$CFLAGS -g3 -DDEBUGGING=1"
    ;;
check)
    CC=gcc
    CFLAGS="$CFLAGS -DDEBUGGING=1 -fanalyzer"
    ;;
build|run)
    CFLAGS="$CFLAGS -O2 -flto -march=native -ftree-vectorize"
    ;;
release)
    CFLAGS="$CFLAGS -DRELEASING=1 -O2 -flto -march=native -ftree-vectorize"
    ;;
fast_feedback)
    ;;
cross)
    common_build_cross_all windows
    cross="$target"

    CFLAGS="$CFLAGS -O2"
    CFLAGS="$CFLAGS -target $cross"

    case "$cross" in
    *windows*)
        exe="bin/$program.exe"
        ;;
    *)
        ;;
    esac
    ;;
build|check|cross|debug|debug-fast|fast_feedback|install|release|run|test|uninstall)
    ;;
*)
    common_build_unknown_mode
    ;;
esac

case "$mode" in
fast_feedback)
    trace_on
    $CC $CPPFLAGS $CFLAGS main.c -o "$exe" $LDFLAGS
    trace_off
    ;;
build|cross|debug|debug-fast|run|release)
    trace_on

    common_build_tags cbase . src
    $CC $CPPFLAGS $CFLAGS main.c -o "$exe" $LDFLAGS

    if [ $mode = "run" ]; then
        if [ -n "$target" ]; then
            $exe "$target"
        else
            $exe
        fi
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
    common_test "$target"
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

case "$mode" in
check)
    set +e
    CC=gcc CFLAGS="-fanalyzer" ./build.sh

    CFLAGS="--analyze -Xanalyzer -analyzer-output=text"
    CFLAGS="$CFLAGS -Xanalyzer -analyzer-werror"
    CFLAGS="$CFLAGS -Xanalyzer -analyzer-opt-analyze-headers"
    CFLAGS="$CFLAGS -Wno-unused-command-line-argument"
    CC=clang CFLAGS="$CFLAGS" ./build.sh

    echo "static analysis finished."
    exit
    ;;
esac
