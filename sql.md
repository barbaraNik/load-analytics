# SQL-разведка: вопросы, запросы, выводы

PostgreSQL, схема `consolidation_planner`, период 06.01.2025 – 23.06.2025, 76 отправок.

Каждый запрос отвечает на один вопрос. 

Ключевая метрика в данных — `f_score`, интегральный коэффициент загрузки контейнера:

```
f_score = 0,6 × использование объёма + 0,3 × использование грузоподъёмности + 0,1 × использование мест
```

---

## 1. Одинаково ли недогружены контейнеры разных типов?


```sql
SELECT container_type_id,
       AVG(load_factor_volume) AS load_factor_volume,
       AVG(load_factor_weight) AS load_factor_weight
FROM consolidations
GROUP BY container_type_id;
```

**Результат**

| Тип | Объём | Вес |
|---|---|---|
| 40DC | 54,8% | 74,5% |
| 20GP | 47,6% | 40,9% |

**Вывод.** Причины недогруза разные. 40DC упирается в грузоподъёмность: место в контейнере
остаётся, но везти уже нельзя. 20GP недобирает по обоим измерениям — его просто отправляют
недокомплектом. Это два разных сценария, и решения у них тоже будут разные.

---

## 2. Связана ли загрузка с количеством номенклатуры в контейнере?

Гипотеза на входе: чем больше разных позиций собрали в отправку, тем плотнее её удаётся уложить.

```sql
SELECT c.consolidation_id,
       c.f_score,
       c.container_type_id,
       COUNT(DISTINCT p.product_id) AS product_count
FROM consolidations AS c
JOIN consolidation_orders AS co ON co.consolidation_id = c.consolidation_id
JOIN orders            AS o  ON o.order_id  = co.order_id
JOIN order_items       AS oi ON oi.order_id = o.order_id
JOIN products          AS p  ON p.product_id = oi.product_id
GROUP BY c.consolidation_id, c.f_score, c.container_type_id
ORDER BY c.f_score;
```

**Вывод.** Контейнеры с самым низким `f_score` не отличаются по числу позиций от остальных.
Разнообразие номенклатуры загрузку не объясняет — смотреть нужно не на количество SKU,
а на их физические характеристики. 

---

## 3. Сколько стоит недогруз?

```sql
SELECT c.container_type_id,
       AVG(c.f_score)          AS avg_f_score,
       AVG(tc.cost_per_kg_rub) AS avg_cost_per_kg_rub
FROM consolidations AS c
JOIN transport_costs AS tc ON tc.consolidation_id = c.consolidation_id
GROUP BY c.container_type_id;
```

Проверка того же показателя расчётом из ставки фрахта и фактического веса:

```sql
SELECT c.container_type_id,
       AVG(c.f_score) AS avg_f_score,
       AVG(tc.freight_rate_usd / c.total_weight_kg) AS avg_cost_per_kg
FROM consolidations AS c
JOIN transport_costs AS tc ON tc.consolidation_id = c.consolidation_id
GROUP BY c.container_type_id;
```

**Результат**

| Тип | Загрузка | Стоимость доставки |
|---|---|---|
| 40DC | 65% | 23,56 ₽/кг |
| 20GP | 51% | 43,65 ₽/кг |

**Вывод.** 20GP почти вдвое дороже в пересчёте на килограмм и при этом хуже загружен.
Прямая точка снижения затрат: часть отправок в 20GP потенциально консолидируется в 40DC.

---

## 4. Что лежит в самых недогруженных контейнерах?

Порог 0,51 — медианная загрузка по выборке.

```sql
SELECT p.name AS product_name,
       COUNT(*) AS cnt
FROM consolidations      AS c
JOIN consolidation_orders AS co ON co.consolidation_id = c.consolidation_id
JOIN orders               AS o  ON o.order_id  = co.order_id
JOIN order_items          AS oi ON oi.order_id = o.order_id
JOIN products             AS p  ON p.product_id = oi.product_id
WHERE c.f_score < 0.51
GROUP BY p.name
ORDER BY cnt DESC
LIMIT 5;
```

**Результат.** В топе — тяжёлые позиции с высокой плотностью: направляющая линейная 1339 кг/м³,
плёнка самоклеящаяся 1287 кг/м³, ткань баннерная 1092 кг/м³, блок управления 1037 кг/м³,
вакуумный прижимной 794 кг/м³.

**Вывод.** Недогруз по объёму — следствие плотности груза: контейнер добирает вес раньше,
чем объём. Отсюда гипотеза о смешивании тяжёлой и лёгкой номенклатуры в одной отправке.


Этого хватило, чтобы перейти от симптома «затраты высокие» к измеримой проблеме
и вынести устойчивые срезы в Power BI.
