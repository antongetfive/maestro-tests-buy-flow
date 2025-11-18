#!/bin/bash

ALLURE_RESULTS_DIR="allure-results"
ARCHIVE_DIR="allure-results-archive"
REPORT_DIR="allure-report"

# Цвета
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
GRAY="\033[0;37m"
NC="\033[0m" # reset

########################################
### Архивация старых результатов
########################################
if [ -d "$ALLURE_RESULTS_DIR" ] && [ "$(ls -A $ALLURE_RESULTS_DIR)" ]; then
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
### Плавная анимация полосы
########################################
animate_loading() {
    local width=20
    local progress=0

    while kill -0 $1 2>/dev/null; do
        bar=""
        for ((i=0; i<$width; i++)); do
            if [ $i -lt $progress ]; then
                bar+="█"
            else
                bar+="░"
            fi
        done

        printf "\r⏳ ${bar}"

        progress=$(( (progress+1) % width ))
        sleep 0.1
    done

    printf "\r"
}

########################################
### Спиннер
########################################
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

########################################
### Прогресс-бар итогов
########################################
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
### Получение IP адреса
########################################
get_ip_address() {
    # Пробуем разные способы получить IP
    local ip=""
    
    # Для macOS
    if command -v ipconfig &> /dev/null; then
        ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
    fi
    
    # Для Linux
    if [ -z "$ip" ] && command -v ip &> /dev/null; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi
    
    # Универсальный способ
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    echo "$ip"
}

########################################
### Запуск теста Maestro
########################################
run_test() {
    FILE="$1"
    NAME=$(basename "$FILE" .yaml)

    echo "------------------------------"
    echo "▶️  Запуск теста: $NAME"
    echo "------------------------------"

    ########################################
    ### Проверка существования файла
    ########################################
    if [ ! -f "$FILE" ]; then
        echo "❌ Файл не найден: $FILE — добавляю в Allure как FAILED"

        cat > "$ALLURE_RESULTS_DIR/${NAME}.xml" <<EOF
<testsuite name="${NAME}" tests="1" failures="1">
    <testcase classname="${NAME}" name="${NAME}">
        <failure message="Test file not found">Flow path does not exist: ${FILE}</failure>
    </testcase>
</testsuite>
EOF

        SYMBOL="${RED}█${NC}"
        PROGRESS_BAR+=("$SYMBOL")
        print_progress
        return
    fi

    ########################################
    ### Файл есть — запускаем Maestro
    ########################################

    maestro test "$FILE" \
        --format=JUNIT \
        --output="$ALLURE_RESULTS_DIR/${NAME}.xml" \
        --test-output-dir="$ALLURE_RESULTS_DIR" &

    TEST_PID=$!

    animate_loading $TEST_PID &
    LOAD_PID=$!

    spinner $TEST_PID

    kill $LOAD_PID 2>/dev/null

    wait $TEST_PID
    EXIT_CODE=$?

    echo ""

    if [ $EXIT_CODE -eq 0 ]; then
        SYMBOL="${GREEN}█${NC}"
        echo -e "✅ $NAME пройден"
    else
        SYMBOL="${RED}█${NC}"
        echo -e "❌ $NAME упал"
    fi

    PROGRESS_BAR+=("$SYMBOL")
    print_progress
}

########################################
### Запуск Python сервера перед тестами
########################################
echo "▶️  Запуск Python скрипта: working_otp_server.py"
python3 working_otp_server.py &
PY_PID=$!

sleep 2
echo "✅ Python сервер запущен (PID=$PY_PID)"

########################################
### Список тестов
########################################
TEST_FILES=(
    "01_ochistka.yaml"
    "02_zapusk.yaml"
    "03_autorization.yaml"
    "04_onbording.yaml"
    "05_yandexPayBilet.yaml"
    "06_stopApp_1.yaml"
    "07_yandexPayBiletEda.yaml"
)

TOTAL_TESTS=${#TEST_FILES[@]}
PROGRESS_BAR=()

for TEST in "${TEST_FILES[@]}"; do
    run_test "$TEST"
done

########################################
### Остановка Python сервера
########################################
echo "⏹ Остановка Python скрипта..."
kill $PY_PID 2>/dev/null
echo "🛑 Python сервер остановлен"

########################################
### Генерация Allure отчета
########################################
echo "📊 Генерация Allure отчёта..."
allure generate "$ALLURE_RESULTS_DIR" --clean -o "$REPORT_DIR"

if [ $? -eq 0 ]; then
    echo "✅ Allure отчёт сгенерирован в папку: $REPORT_DIR"
    
    # Получаем IP адрес для доступа из сети
    LOCAL_IP=$(get_ip_address)
    PORT=8080
    
    echo ""
    echo "🌐 ${BLUE}ДОСТУП К ОТЧЕТУ:${NC}"
    echo "----------------------------------------"
    echo -e "${YELLOW}📍 Локальный доступ:${NC}"
    echo -e "   http://localhost:$PORT"
    echo ""
    echo -e "${YELLOW}🌍 Доступ для команды:${NC}"
    if [ -n "$LOCAL_IP" ]; then
        echo -e "   http://$LOCAL_IP:$PORT"
        echo ""
        echo -e "${GREEN}📢 Сообщите команде этот адрес для доступа к отчету${NC}"
    else
        echo -e "   ${RED}Не удалось определить IP адрес${NC}"
        echo -e "   ${GRAY}Проверьте сетевое подключение${NC}"
    fi
    echo "----------------------------------------"
    
    # Запускаем сервер для локального просмотра
    echo ""
    echo "🚀 Запуск Allure сервера на порту $PORT..."
    echo "💡 Для остановки сервера нажмите Ctrl+C"
    echo ""
    
    # Запускаем сервер в фоне и сохраняем PID
    allure serve --port $PORT "$ALLURE_RESULTS_DIR" &
    ALLURE_PID=$!
    
    # Ждем немного чтобы сервер успел запуститься
    sleep 3
    
    # Показываем активные подключения
    echo -e "${BLUE}📊 Статус сервера:${NC}"
    if command -v lsof &> /dev/null; then
        echo "Порт $PORT прослушивается:"
        lsof -i :$PORT 2>/dev/null || echo "Сервер запускается..."
    fi
    
    # Ждем завершения сервера
    wait $ALLURE_PID
    
else
    echo "❌ Ошибка генерации Allure отчёта"
    exit 1
fi
