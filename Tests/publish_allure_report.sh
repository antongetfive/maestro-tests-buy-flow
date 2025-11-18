#!/bin/bash

# -------------------------------
# 1) Настройки
# -------------------------------
DOCS_DIR="docs"
RESULTS_DIR="allure-results"
REPO_URL=$(git config --get remote.origin.url)

if [ -z "$REPO_URL" ]; then
  echo "❌ Ошибка: git репозиторий не найден."
  exit 1
fi

# -------------------------------
# 2) Проверяем наличие allure-results
# -------------------------------
if [ ! -d "$RESULTS_DIR" ]; then
  echo "❌ Папка $RESULTS_DIR не найдена!"
  exit 1
fi

# -------------------------------
# 3) Очистка docs/
# -------------------------------
echo "🧹 Очищаю $DOCS_DIR..."
rm -rf "$DOCS_DIR"
mkdir "$DOCS_DIR"

# -------------------------------
# 4) Генерация отчёта
# -------------------------------
echo "📊 Генерирую Allure Report..."
allure generate "$RESULTS_DIR" --clean -o "$DOCS_DIR"

if [ $? -ne 0 ]; then
  echo "❌ Ошибка генерации отчёта!"
  exit 1
fi

# -------------------------------
# 5) Git commit + push
# -------------------------------
echo "📤 Делаю commit + push..."

git add -A

if git diff --cached --quiet; then
  echo "ℹ️ Нечего коммитить — отчёт не изменился."
else
  git commit -m "update reports $(date)"
  git push origin HEAD
fi

# -------------------------------
# 6) Генерация ссылки GitHub Pages
# -------------------------------
USER=$(echo "$REPO_URL" | sed -E 's#.*github.com[:/](.*)/(.*)\.git#\1#')
REPO=$(echo "$REPO_URL" | sed -E 's#.*github.com[:/](.*)/(.*)\.git#\2#')

GH_PAGES_URL="https://${USER}.github.io/${REPO}/"

# -------------------------------
# 7) Готово
# -------------------------------
echo ""
echo "🎉 Отчёт успешно опубликован!"
echo "🔗 GitHub Pages:"
echo "$GH_PAGES_URL"
echo ""
echo "Если Pages настроен на /docs — отчёт уже доступен."
