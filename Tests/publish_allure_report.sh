rm -rf docs
mkdir docs

# соберём все allure-results из подпроектов
RESULTS=""

for DIR in maestro-tests-buy-flow/*; do
  if [ -d "$DIR/allure-results" ]; then
    RESULTS="$RESULTS $DIR/allure-results"
  fi
done

echo "Используем результаты:"
echo $RESULTS

# генерируем единый отчёт
allure generate $RESULTS --clean -o docs

git add -A
git commit -m "update reports $(date)"
git push
