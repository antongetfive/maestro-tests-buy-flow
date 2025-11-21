#!/bin/bash
trap "echo '⛔ Stopping...'; kill $PY_PID 2>/dev/null; exit 1" INT

ALLURE_RESULTS_DIR="allure-results"
ARCHIVE_DIR="allure-results-archive"
REPORT_DIR="allure-report"

# Цвета
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
GRAY="\033[0;37m"
NC="\033[0m"

########################################
### Архивация старых результатов
########################################
if [ -d "$ALLURE_RESULTS_DIR" ] && [ "$(ls -A "$ALLURE_RESULTS_DIR")" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "$ARCHIVE_DIR"
    mv "$ALLURE_RESULTS_DIR" "$ARCHIVE_DIR/allure-results_$TIMESTAMP"
    echo "✅ Старые результаты перемещены в архив: $ARCHIVE_DIR/allure-results_$TIMESTAMP"
fi

mkdir -p "$ALLURE_RESULTS_DIR"

########################################
### Allure metadata
########################################
echo "allure.project.name=Payment Flow Tests" > "$ALLURE_RESULTS_DIR/allure.properties"

cat > "$ALLURE_RESULTS_DIR/environment.properties" <<EOF
DEVICE=Android Physical Device
PLATFORM=Android(Production)
APP_VERSION=1.0.0
TEST_RUNNER=Maestro
EOF

cat > "$ALLURE_RESULTS_DIR/executor.json" <<EOF
{
  "name": "Sergeev Anton",
  "type": "QA",
  "url": "http://localhost",
  "buildName": "QA",
  "buildOrder": 1,
  "reportName": "Payment Flow Tests Report"
}
EOF

########################################
### Анимации
########################################
animate_loading() {
    local width=20
    local progress=0
    while kill -0 $1 2>/dev/null; do
        bar=""
        for ((i=0; i<$width; i++)); do
            if [ $i -lt $progress ]; then bar+="█"; else bar+="░"; fi
        done
        printf "\r⏳ ${bar}"
        progress=$(( (progress+1) % width ))
        sleep 0.1
    done
    printf "\r"
}

spinner() {
    local pid=$1
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r🔄  Выполняется: ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r"
}

print_progress() {
    printf "\nПрогресс: ["
    for ((i=0; i<TOTAL_TESTS; i++)); do
        if [ $i -lt ${#PROGRESS_BAR[@]} ]; then
            printf "%s" "${PROGRESS_BAR[i]}"
        else
            printf "${GRAY}░${NC}"
        fi
    done
    printf "] %d%%\n\n" $(( ${#PROGRESS_BAR[@]} * 100 / TOTAL_TESTS ))
}

########################################
### Запуск теста Maestro
########################################
run_test() {
    FILE="$1"
    SESSION_TIME="$2"
    NAME=$(basename "$FILE" .yaml)

    echo "------------------------------"
    echo "▶️  Запуск теста: $NAME"
    echo "------------------------------"

    if [ ! -f "$FILE" ]; then
        echo "❌ Файл не найден: $FILE — добавляю в Allure как FAILED"
        cat > "$ALLURE_RESULTS_DIR/${NAME}.xml" <<EOF
<testsuite name="${NAME}" tests="1" failures="1">
    <testcase classname="${NAME}" name="${NAME}">
        <failure message="Test file not found">Flow path does not exist: ${FILE}</failure>
    </testcase>
</testsuite>
EOF
        PROGRESS_BAR+=("${RED}█${NC}")
        print_progress
        return
    fi

    if [[ -n "$SESSION_TIME" ]]; then
        echo "⏱  Используется session_time: $SESSION_TIME"
        maestro test "$FILE" \
            -e session_time="$SESSION_TIME" \
            --format=JUNIT \
            --output="$ALLURE_RESULTS_DIR/${NAME}.xml" \
            --test-output-dir="$ALLURE_RESULTS_DIR" &
    else
        maestro test "$FILE" \
            --format=JUNIT \
            --output="$ALLURE_RESULTS_DIR/${NAME}.xml" \
            --test-output-dir="$ALLURE_RESULTS_DIR" &
    fi

    TEST_PID=$!

    animate_loading $TEST_PID &
    LOAD_PID=$!

    spinner $TEST_PID
    kill $LOAD_PID 2>/dev/null

    wait $TEST_PID
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ $NAME пройден"
        PROGRESS_BAR+=("${GREEN}█${NC}")
    else
        echo "❌ $NAME упал"
        PROGRESS_BAR+=("${RED}█${NC}")
    fi

    print_progress
}

########################################
### Запуск Python сервера
########################################
echo "▶️  Запуск Python скрипта: working_otp_server.py"
python3 working_otp_server.py &
PY_PID=$!

sleep 2
echo "✅ Python сервер запущен (PID=$PY_PID)"

########################################
### Чтение tests.txt (с временем)
########################################
TESTS=()
TIMES=()

while read -r test_file session_time; do
    [[ -z "$test_file" || "$test_file" == \#* ]] && continue
    TESTS+=("$test_file")
    TIMES+=("$session_time")
done < tests.txt

TOTAL_TESTS=${#TESTS[@]}
PROGRESS_BAR=()

########################################
### Запуск тестов
########################################
for i in "${!TESTS[@]}"; do
    run_test "${TESTS[$i]}" "${TIMES[$i]}"
done

########################################
### Остановка Python сервера
########################################
echo "⏹ Остановка Python сервера..."
kill $PY_PID 2>/dev/null
echo "🛑 Python сервер остановлен"

########################################
### Звук окончания
########################################
echo "🔔 Все тесты завершены!"
afplay /System/Library/Sounds/Glass.aiff

########################################
### Allure отчёт
########################################
echo "📊 Генерация Allure отчёта..."
allure generate "$ALLURE_RESULTS_DIR" --clean -o "$REPORT_DIR"

if [ $? -eq 0 ]; then
    echo "✅ Отчёт сгенерирован"
    echo "🌐 Открываю отчёт..."
    allure open "$REPORT_DIR"
else
    echo "❌ Ошибка генерации отчёта"
    exit 1
fi
