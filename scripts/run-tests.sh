#!/bin/sh
# Headless checks. One command from the repo root. Does not build the Mac app
# and does not need a host or a GPU.
set -eu
cd "$(dirname "$0")/.."

echo "== python =="
python3 tests/mock_host_test.py
python3 tests/preference_persistence_test.py
python3 tests/stream_quit_teardown_test.py
python3 tests/macos_minos_test.py
python3 tests/macos_availability_test.py
python3 tests/macos_deployment_target_test.py
python3 tests/macos_store_prep_test.py
python3 tests/v2_qml_imports_test.py
python3 tests/twilight_shell_behavior_test.py

echo "== c++ logic =="
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/codec_offer_test.cpp -Iapp -o /tmp/codec_offer_test
/tmp/codec_offer_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/corehid_mouse_test.cpp \
  app/streaming/input/corehid_mouse_decoder.cpp \
  -Iapp/streaming/input \
  -o /tmp/corehid_mouse_test
/tmp/corehid_mouse_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/bitrate_choice_test.cpp -Iapp/settings -o /tmp/bitrate_choice_test
/tmp/bitrate_choice_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/vsync_choice_test.cpp -Iapp/settings -o /tmp/vsync_choice_test
/tmp/vsync_choice_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/adaptive_bitrate_test.cpp -Iapp/streaming -o /tmp/adaptive_bitrate_test
/tmp/adaptive_bitrate_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/twilight_hud_parse_test.cpp app/gui/streamhudparse.cpp \
  -Iapp/gui -o /tmp/hud_parse_test
/tmp/hud_parse_test
g++ -std=c++17 -Wall -Wextra -Werror \
  tests/update_version_test.cpp app/backend/updateversion.cpp \
  -Iapp -Iapp/backend -o /tmp/update_version_test
/tmp/update_version_test

echo "== qt =="
if ! command -v qmake6 >/dev/null 2>&1; then
  echo "qmake6 is not installed. Install Qt 6 (qmake6, Qt Quick, Qt Test) and run this again." >&2
  exit 1
fi
mkdir -p build/headless-tests
(
  cd build/headless-tests
  qmake6 ../../tests/twilight_qt_tests.pro
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
)
if [ -x build/headless-tests/twilight_qt_tests ]; then
  BIN=build/headless-tests/twilight_qt_tests
elif [ -x build/headless-tests/release/twilight_qt_tests ]; then
  BIN=build/headless-tests/release/twilight_qt_tests
else
  echo "Qt test binary was not produced" >&2
  exit 1
fi
QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" "$BIN"
echo "headless tests passed"
