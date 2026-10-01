-- Вопрос: одинаково ли недогружены контейнеры разных типов и по какому измерению —
--          по объёму или по грузоподъёмности?
-- Результат: 40DC — вес 74,5% при объёме 54,8%; 20GP — вес 40,9% при объёме 47,6%.
-- Вывод:    причины недогруза разные. 40DC упирается в грузоподъёмность: место в контейнере
--           остаётся, но везти уже нельзя. 20GP недобирает по обоим измерениям —
--           его отправляют недокомплектом.

SELECT container_type_id,
       AVG(load_factor_volume) AS load_factor_volume,
       AVG(load_factor_weight) AS load_factor_weight
FROM consolidations
GROUP BY container_type_id;


-- Вопрос: связана ли загрузка контейнера с тем, сколько разной номенклатуры в него собрали?
--          Гипотеза на входе: чем больше разных SKU, тем плотнее удаётся собрать контейнер.
-- Результат: контейнеры с самым низким f_score не отличаются по числу позиций от остальных.
-- Вывод:    разнообразие номенклатуры само по себе загрузку не объясняет — проверять нужно
--           не количество SKU, а их физические характеристики (см. запрос 04).

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


-- Вопрос: во сколько обходится недогруз — есть ли разница в стоимости доставки килограмма
--          между типами контейнеров?
-- Результат: 20GP — 43,65 ₽/кг при загрузке 51%; 40DC — 23,56 ₽/кг при загрузке 65%.
-- Вывод:    20GP почти вдвое дороже в пересчёте на килограмм и при этом хуже загружен.
--           Это прямая точка снижения затрат: часть отправок в 20GP потенциально
--           консолидируется в 40DC.

-- Вариант A — по готовому полю стоимости
SELECT c.container_type_id,
       AVG(c.f_score)          AS avg_f_score,
       AVG(tc.cost_per_kg_rub) AS avg_cost_per_kg_rub
FROM consolidations AS c
JOIN transport_costs AS tc ON tc.consolidation_id = c.consolidation_id
GROUP BY c.container_type_id;

-- Вариант B — расчёт из ставки фрахта и фактического веса (проверка варианта A)
SELECT c.container_type_id,
       AVG(c.f_score) AS avg_f_score,
       AVG(tc.freight_rate_usd / c.total_weight_kg) AS avg_cost_per_kg
FROM consolidations AS c
JOIN transport_costs AS tc ON tc.consolidation_id = c.consolidation_id
GROUP BY c.container_type_id;


-- Вопрос: какая номенклатура чаще всего оказывается в самых недогруженных контейнерах?
--          Порог 0,51 — медианная загрузка по выборке.
-- Результат: в топе — тяжёлые позиции с высокой плотностью (направляющая линейная 1339 кг/м³,
--            плёнка самоклеящаяся 1287 кг/м³, ткань баннерная 1092 кг/м³).
-- Вывод:     недогруз по объёму — следствие плотности груза: контейнер добирает вес раньше,
--            чем объём. Отсюда гипотеза о смешивании тяжёлой и лёгкой номенклатуры
--            в одной отправке.

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
