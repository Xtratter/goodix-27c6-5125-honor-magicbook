# Свой матчер для Goodix 27c6:5125, этап 1 (M0-M2): план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Собрать набор касаний сканера, измерить базовые линии (`openchicago` и приближение SIGFM), построить прототип матчера B (BLPOC) на Python и принять решение по критерию спецификации (проходит ли B).

**Architecture:** Отдельный репозиторий-лаборатория на Python (`~/src/goodix5125-matcher-lab`). Общий интерфейс `Matcher`, одинаковый для базовых линий и кандидата; один раннер оценки считает метрики по протоколам и разбиению «разработка / отложенные 20%». `openchicago` подключается как чёрный ящик через тонкую C-обёртку (ctypes) только по публичному заголовку. Сбор касаний выполняет существующий скрипт автора драйвера, вызываемый на месте без копирования его кода.

**Tech Stack:** Python 3.14 (venv, pip), numpy, opencv-python-headless (только для приближения SIGFM и поворота изображений), pyusb (сбор), pytest; C (glib) для обёртки; meson/ninja для сборки `openchicago` вне его дерева.

**Spec:** `docs/superpowers/specs/2026-10-09-goodix5125-clean-matcher-design.md` (в репозитории заметок `goodix-27c6-5125-honor-magicbook`).

## Global Constraints

- Новый код лаборатории и будущего матчера: лицензия LGPL-2.1-or-later (в каждом файле `.py`/`.c` строка `SPDX-License-Identifier: LGPL-2.1-or-later`).
- **Правило чистоты:** при написании матчера B и любого кода из `lab/matchers/blpoc*.py` **не открывать и не читать** исходники `openchicago/src/` и `libfprint/drivers/goodix5125/chicago/`. Допустим только публичный заголовок `openchicago/include/openchicago.h`.
- Код Windows-драйвера (DLL, пакет «Firmware») не копируется и не используется; пакет «Firmware» **не распаковывается в рабочие каталоги и не прошивается**.
- Кадры - биометрические данные: каталог `data/` и файлы `*.npz` в `.gitignore`, в git и в отчёты попадают только агрегированные числа.
- Скрипты автора драйвера (`tools/collect.py` и его модули) **не копируются** в наш репозиторий (у репозитория нет файла лицензии): вызываются по месту из `~/src/FingerprintDriver_27c6_5125`.
- Набор: 15 `varied`, 15 `natural-1`, 15 `natural-2`, 30 `impostor`; отложенные 20% нетронуты до задачи 12, итоговая оценка по ним **один раз**.
- Метрики и зерно: главная - FRR при FAR=0 и зазор между худшим «своим» и лучшим «чужим» баллом; фиксированное зерно `20261009`; FAR<=1% только с оговоркой о малом объёме.
- Тяжёлые сборки (meson/ninja) только в щадящем режиме: `nice -n 19 ionice -c3 taskset -c 0,1` (две перезагрузки ноутбука при сборке на 16 потоках).
- Критерий этапа: FRR@FAR0 у B не выше, чем у `openchicago`, и зазор не меньше (с учётом доверительных интервалов, раздел задачи 12); иначе остановка или кандидат C по решению пользователя.
- Коммиты в локальный репозиторий лаборатории с автором `Xtratter <1359019+Xtratter@users.noreply.github.com>`; отправка на GitHub только по прямому разрешению пользователя.

## Review Focus

1. Пустой кадр (палец не положен) или кадр, где `background - frame` равен нулю во всех пикселях: матчеры обязаны вернуть «кадр отклонён» (`None`), а не `NaN`, деление на ноль или исключение (тесты в задачах 3, 8 и 11).
2. Утечка между регистрацией и пробами: четыре кадра одного касания не должны попасть и в регистрацию, и в пробы (тест в задаче 4).
3. Повреждённая или неполная сессия (сбор прерван, форма массива не `(N,4,5120)`): загрузчик помечает ошибку, а не падает и не загружает мусор (задача 2).
4. Утечка отложенной части в подбор параметров: код настройки не должен читать отложенные касания, а повторный запуск итоговой оценки без `--force` отказывается (задачи 4 и 12).
5. Касания разных сессий с разным базовым кадром: матчер использует базовый кадр **своего** касания, а не первого (тест в задаче 9).

---

### Task 1: Каркас репозитория-лаборатории

**Files:**
- Create: `~/src/goodix5125-matcher-lab/{pyproject.toml,.gitignore,README.md,lab/__init__.py,tests/test_smoke.py}`

**Interfaces:**
- Produces: окружение `.venv` с numpy, opencv-python-headless, pyusb, pytest; команда проверки `.venv/bin/python -m pytest -q`.

- [ ] **Step 1: Создать каталог, `git init -b main`, локальную идентичность автора (`git config user.name/user.email`).**
- [ ] **Step 2: Написать `tests/test_smoke.py::test_imports`**, который импортирует `numpy`, `cv2`, `lab` и проверяет `numpy.__version__`.
- [ ] **Step 3: `python3 -m venv .venv && .venv/bin/pip install numpy opencv-python-headless pyusb pytest`** (сеть, без `sudo`); записать зависимости в `pyproject.toml` (`requires-python = ">=3.13"`).
- [ ] **Step 4: `.gitignore` с `.venv/`, `data/`, `*.npz`, `build/`, `__pycache__/`; `README.md` с одной страницей: цель, ссылка на спецификацию и план, правило чистоты.**
- [ ] **Step 5: Запустить `.venv/bin/python -m pytest -q`; ожидается `1 passed`.**
- [ ] **Step 6: Commit** (`git add -A && git commit -m "chore: lab scaffold"`).

### Task 2: Загрузка набора (`lab/dataset.py`)

**Files:**
- Create: `lab/dataset.py`, `tests/test_dataset.py`

**Interfaces:**
- Produces: `@dataclass(frozen=True) class Touch: session: str; label: str; index: int; background: np.ndarray; frame: np.ndarray` (оба `uint16`, форма `(80, 64)`; `frame` - кадр с индексом 2 из `[background, first, full, late]`).
- Produces: `load_session(path: Path, frame_index: int = 2) -> list[Touch]`; бросает `DatasetError(ValueError)` при форме не `(N,4,5120)` или типе не `uint16`.
- Produces: `load_dataset(root: Path) -> dict[str, list[Touch]]` (ключ - метка группы: `varied`, `natural-1`, `natural-2`, `impostor`); неполные файлы пропускаются с записью в `dataset.warnings`.

- [ ] **Step 1: Тесты** (синтетические `.npz` в `tmp_path`): `test_load_session_shapes` (3 касания -> 3 `Touch`, `frame.shape == (80, 64)`), `test_load_session_rejects_bad_shape` (`(3,3,5120)` -> `DatasetError`), `test_load_dataset_groups_by_label` (имена `varied-2026....npz` и `impostor-...npz`), `test_partial_session_is_skipped_with_warning`.
- [ ] **Step 2: Запустить `pytest tests/test_dataset.py -q`; ожидается FAIL (`ModuleNotFoundError`).**
- [ ] **Step 3: Реализовать `lab/dataset.py` по интерфейсам выше**; метка берётся из имени файла до первого `-` после которого идёт штамп времени (`natural-1-2026...` -> `natural-1`).
- [ ] **Step 4: Запустить тесты; ожидается PASS.**
- [ ] **Step 5: Commit.**

### Task 3: Предобработка, общая для кандидатов (`lab/frames.py`) и метрики (`lab/metrics.py`)

**Files:**
- Create: `lab/frames.py`, `lab/metrics.py`, `tests/test_frames.py`, `tests/test_metrics.py`

**Interfaces:**
- Produces: `ridge_signal(touch: Touch) -> np.ndarray | None` - `float32` формы `(80, 64)`: `clip(background - frame, 0)`; `None`, если сигнал нулевой или его стандартное отклонение ниже `1e-6` (пустой кадр).
- Produces: `frr_at_far(genuine: Sequence[float], impostor: Sequence[float], far: float = 0.0) -> float` - порог `t` - наименьшее значение, при котором доля «чужих» с баллом строго выше `t` не больше `far` (для `far=0` это `max(impostor)`); «свой» принимается, если его балл строго выше `t`; результат - доля отвергнутых «своих».
- Produces: `gap(genuine, impostor) -> float` = `min(genuine) - max(impostor)`; `normalized_gap(genuine, impostor) -> float` = `gap / (median(genuine) - median(impostor))`, `nan` при нуле в знаменателе.
- Produces: `bootstrap_ci(metric: Callable, genuine, impostor, n: int = 1000, seed: int = 20261009, alpha: float = 0.05) -> tuple[float, float]`.

- [ ] **Step 1: Тесты метрик с точными числами:** `test_frr_far0_separable` (`genuine=[5,6,7]`, `impostor=[1,2,3]` -> `0.0`), `test_frr_far0_overlap` (`genuine=[2,6,7]`, `impostor=[1,2,3]` -> `1/3`), `test_gap` (`gap([5,6],[1,4]) == 1`), `test_gap_negative_when_overlapping`, `test_bootstrap_ci_is_deterministic_for_seed`.
- [ ] **Step 2: Тесты кадров:** `test_ridge_signal_empty_returns_none` (кадр равен фону -> `None`), `test_ridge_signal_nonnegative_and_shape`, `test_ridge_signal_constant_offset_returns_none`.
- [ ] **Step 3: Запустить, увидеть FAIL; реализовать модули; запустить, увидеть PASS.**
- [ ] **Step 4: Commit.**

### Task 4: Протоколы и разбиение (`lab/protocols.py`)

**Files:**
- Create: `lab/protocols.py`, `tests/test_protocols.py`

**Interfaces:**
- Consumes: `Touch`, `load_dataset`.
- Produces: `@dataclass class Fold: enroll: list[Touch]; genuine: list[Touch]; impostor: list[Touch]; protocol: str; repeat: int`.
- Produces: `split_dev_holdout(touches: Sequence[Touch], holdout_fraction: float = 0.2, seed: int = 20261009) -> tuple[list[Touch], list[Touch]]` - детерминированно, разбиение по **касаниям**, стратифицировано по меткам групп.
- Produces: `make_folds(dataset: dict[str, list[Touch]], protocol: str, repeats: int = 5, seed: int = 20261009, enroll_size: int = 12) -> list[Fold]` для `protocol in {"varied->natural", "natural-1->natural-2"}`; регистрация случайным подмножеством из `enroll_size` касаний; пробы - все остальные «свои» целевой группы; «чужие» - все.
- Produces: `class HoldoutGuard` - `check_dev_only(touches)` бросает `HoldoutLeakError`, если среди касаний есть отложенное.

- [ ] **Step 1: Тесты:** `test_split_is_deterministic`, `test_holdout_fraction_per_group` (из 15 касаний 3 отложенных), `test_no_touch_in_both_enroll_and_probe`, `test_same_touch_frames_never_split` (проверка по `(session, label, index)`), `test_folds_use_only_dev_touches`, `test_holdout_guard_raises_on_leak`.
- [ ] **Step 2: FAIL -> реализовать -> PASS.**
- [ ] **Step 3: Commit.**

### Task 5: Интерфейс матчера и раннер оценки (`lab/matcher.py`, `lab/evaluate.py`)

**Files:**
- Create: `lab/matcher.py`, `lab/evaluate.py`, `tests/test_evaluate.py`

**Interfaces:**
- Produces (`lab/matcher.py`): `class Matcher(Protocol): name: str; def enroll(self, touches: Sequence[Touch]) -> object; def score(self, template: object, touch: Touch) -> float | None` (`None` - кадр отклонён, повторить касание).
- Produces (`lab/evaluate.py`): `@dataclass class Report: matcher: str; protocol: str; frr_far0: float; frr_far1: float; gap: float; normalized_gap: float; rejected_genuine: float; rejected_impostor: float; mean_score_ms: float; n_genuine: int; n_impostor: int; ci_frr_far0: tuple[float, float]`.
- Produces: `evaluate(matcher: Matcher, folds: Sequence[Fold]) -> Report` - отклонённые кадры не входят в FRR, но считаются в `rejected_*`; время считается на `score`.

- [ ] **Step 1: Тесты с поддельным матчером:** `test_evaluate_perfect_matcher` (балл «своих» 10, «чужих» 0 -> `frr_far0 == 0.0`, `gap == 10`), `test_evaluate_counts_rejections` (часть кадров -> `None`), `test_evaluate_uses_each_fold_template`, `test_evaluate_raises_if_no_genuine_scores`.
- [ ] **Step 2: FAIL -> реализовать -> PASS.**
- [ ] **Step 3: Commit.**

### Task 6: Обёртка сбора касаний (`tools/collect_session.py`)

**Files:**
- Create: `tools/collect_session.py`, `tests/test_collect_session.py`, `docs/collecting.md`

**Interfaces:**
- Produces: `GROUPS: dict[str, tuple[int, str]]` - метка -> (число касаний, подсказка): `varied` (15), `natural-1` (15), `natural-2` (15), `impostor` (30, подсказка называет палец).
- Produces: `build_command(label: str, repo: Path, python: Path) -> list[str]` - команда вызова `repo/tools/collect.py LABEL COUNT "prompt"` с рабочим каталогом `repo/tools`.
- Produces: `import_outputs(repo: Path, dest: Path, since: float) -> list[Path]` - копирует новые `repo/dumps/dataset/*.npz` в `dest` (без `*.json` с ответами FDT).

- [ ] **Step 1: Тесты без железа:** `test_groups_counts_match_spec` (15/15/15/30), `test_build_command_uses_repo_tools_cwd`, `test_import_outputs_copies_only_newer_npz` (во временных каталогах).
- [ ] **Step 2: FAIL -> реализовать -> PASS.**
- [ ] **Step 3: Прочитать `~/src/FingerprintDriver_27c6_5125/tools/capture.py` и убедиться, что набор разрешённых команд не содержит прошивочных (`0xa4`, `0xf0`, `0xf2`, `0xf4`) и записи PSK (`0xe0`); результат проверки записать в `docs/collecting.md`.** Если найдено запрещённое - остановиться и сообщить пользователю.
- [ ] **Step 4: `docs/collecting.md`:** пошагово: (1) правило udev `70-goodix-5125.rules` из репозитория автора копируется в `/etc/udev/rules.d/` (пользователь выполняет `sudo`), (2) `sudo systemctl stop fprintd`, (3) запуск, (4) `sudo systemctl start fprintd`, (5) проверка `fprintd-verify`.
- [ ] **Step 5: Commit.**

### Task 7: Сбор набора (интерактивно, с пользователем)

**Files:**
- Create: `data/<сессия>/*.npz` (не в git), `lab/summary.py`, `tests/test_summary.py`

**Interfaces:**
- Produces: `summarize(dataset: dict[str, list[Touch]]) -> dict[str, dict]` - по группам: число касаний, доля пустых (`ridge_signal is None`), медиана энергии сигнала.

- [ ] **Step 1: Тесты `summarize`** на синтетических касаниях: `test_summary_counts_and_empty_fraction`.
- [ ] **Step 2: FAIL -> реализовать -> PASS; commit.**
- [ ] **Step 3: Пользователь выполняет подготовку из `docs/collecting.md` (udev, остановка fprintd); ассистент запускает `collect_session.py` по группам `varied`, `natural-1`; пользователь прикладывает палец по подсказкам.**
- [ ] **Step 4: Через несколько часов группа `natural-2`; затем `impostor` (5 пальцев по 6 касаний).**
- [ ] **Step 5: Проверка: `python -m lab.summary` показывает 15/15/15/30 касаний и долю пустых кадров ниже 10%.** Если выше - повторить сбор этой группы.
- [ ] **Step 6: Запустить fprintd обратно, убедиться `fprintd-verify` -> `verify-match`.**

### Task 8: Базовая линия A, приближение SIGFM (необязательная, `lab/matchers/sift_pairwise.py`)

**Files:**
- Create: `lab/matchers/__init__.py`, `lab/matchers/sift_pairwise.py`, `tests/test_sift_pairwise.py`

**Interfaces:**
- Produces: `class SiftPairwiseMatcher(Matcher)`; `name = "sift-pairwise"`. Параметры из исследований автора драйвера: отношение Лоу `0.75`, допуск длин `0.05`, допуск углов `0.05`, минимум совпадений `5`. Балл - число согласованных совпадений; `None` для пустого кадра.
- Примечание в докстринге: это **приближение** SIGFM из libfprint (исходник SIGFM в нашем дереве отсутствует), не точная копия.

- [ ] **Step 1: Тесты:** `test_identical_texture_scores_above_min` (синтетическая текстура с гребнями, один и тот же кадр -> балл не ниже 5), `test_unrelated_texture_scores_zero_or_low`, `test_empty_frame_returns_none`.
- [ ] **Step 2: FAIL -> реализовать (SIFT из OpenCV, парное сопоставление с проверкой согласованности длин и углов между парами) -> PASS.**
- [ ] **Step 3: Commit.**

### Task 9: Базовая линия `openchicago` через обёртку (`shim/`, `lab/matchers/chicago.py`)

**Files:**
- Create: `shim/ocshim.c`, `shim/build.sh`, `lab/matchers/chicago.py`, `tests/test_chicago.py`

**Interfaces:**
- Consumes: публичный заголовок `~/src/FingerprintDriver_27c6_5125/openchicago/include/openchicago.h` (только он; исходники `openchicago/src/` не читать).
- Produces (C, `shim/ocshim.c`): `int ocs_enroll(const uint16_t *backgrounds, const uint16_t *frames, int n_frames, uint8_t **tpl, size_t *tpl_len)` (оба массива по `n_frames * 5120` значений, фон - свой у каждого кадра) - создаёт сеанс `oc_session_new` из транспонированного фона **первого** кадра (`oc_frame_transpose`), `oc_enroll_begin(OC_ENROLL_ENGINE, 12)`, добавляет кадры (каждый предварительно `oc_session_rebase` на фон **своего** касания, затем транспонирование) пока не `complete`, возвращает упакованный шаблон; `int ocs_score(const uint8_t *tpl, size_t tpl_len, const uint16_t *background, const uint16_t *frame, int *score, int *reject)` - `oc_identify` с одним шаблоном; освобождение `void ocs_free(uint8_t *tpl)`.
- Produces (Python): `class ChicagoMatcher(Matcher)`; `name = "openchicago"`; `score` возвращает `None`, если `reject != 0`, иначе `float(score)`.

- [ ] **Step 1: `shim/build.sh`:** `nice -n 19 ionice -c3 taskset -c 0,1 meson setup build/oc ~/src/FingerprintDriver_27c6_5125/openchicago && ninja -C build/oc`, затем компиляция `ocshim.c` в `build/libocshim.so` (`cc -shared -fPIC ... $(pkg-config --cflags --libs glib-2.0)` и `build/oc/libopenchicago.a`).
- [ ] **Step 2: Тест `test_shim_loads` (`ctypes.CDLL` поднимается, `ocs_score` отвечает ошибкой на пустой шаблон без падения) и интеграционный `test_enroll_then_score_matches_own_touch` с пометкой `@pytest.mark.dataset` (пропускается без набора): шаблон из 12 касаний `varied`, проба - касание из `natural-1` -> `score` не `None`.**
- [ ] **Step 3: Тест `test_background_of_each_touch_is_used`: подменить фон пробы на фон другого касания и убедиться, что результат меняется или не `None` по-другому (проверка, что фон передаётся каждому касанию).**
- [ ] **Step 4: Собрать, реализовать `ChicagoMatcher` (ctypes), прогнать тесты; PASS.**
- [ ] **Step 5: Commit.**

### Task 10: Замер базовых линий (`reports/baselines.md`)

**Files:**
- Create: `lab/run_eval.py`, `reports/baselines.md`, `tests/test_run_eval.py`

**Interfaces:**
- Produces: CLI `python -m lab.run_eval --matcher {openchicago,sift-pairwise,blpoc} --protocol {varied->natural,natural-1->natural-2} --split dev` печатает `Report` в виде таблицы; `--split holdout` разрешено только в задаче 12.

- [ ] **Step 1: Тест `test_cli_refuses_holdout_without_flag` и `test_cli_dev_split_only_by_default`.**
- [ ] **Step 2: FAIL -> реализовать -> PASS.**
- [ ] **Step 3: Запустить оба протокола для `openchicago` и `sift-pairwise` на `dev`; записать в `reports/baselines.md` только агрегаты (FRR@FAR0 с доверительным интервалом, зазор, доля отклонённых, время).**
- [ ] **Step 4: Commit (отчёт без кадров).**

### Task 11: Прототип B, BLPOC (`lab/matchers/blpoc.py`)

**Files:**
- Create: `lab/matchers/blpoc.py`, `lab/matchers/blpoc_config.json`, `tests/test_blpoc.py`
- **Правило чистоты действует в полной мере** (см. Global Constraints).

**Interfaces:**
- Consumes: `Touch`, `ridge_signal`, `Matcher`.
- Produces: `prepare(touch: Touch, sigma: float = 4.0) -> np.ndarray | None` - `ridge_signal`, вычитание размытия Гаусса `sigma`, нулевое среднее, единичная дисперсия, окно Ханна; `float32 (80, 64)`; `None` для пустого.
- Produces: `coverage(img: np.ndarray, block: int = 8, var_threshold: float = 0.05) -> float` - доля блоков с дисперсией выше порога; `quality(img: np.ndarray, block: int = 8) -> float` - средний контраст гребней в покрытых блоках (нормированный в `0..1`).
- Produces: `blpoc(a: np.ndarray, b: np.ndarray, band: tuple[float, float] = (0.05, 0.42), pad: int = 128) -> tuple[float, float, tuple[int, int]]` - `(peak, psr, (dy, dx))`: перекрёстный спектр мощности с нормировкой на амплитуду в полосе частот, обратное БПФ, пик и отношение пика к боковым пикам (`psr`).
- Produces: `best_over_rotations(probe: np.ndarray, patch: np.ndarray, angles: Sequence[float]) -> tuple[float, float, tuple[int, int]]` - `(psr, angle, shift)`; повернуть пробу `cv2.warpAffine`.
- Produces: `overlap_fraction(shape: tuple[int, int], shift: tuple[int, int]) -> float` - доля площади перекрытия при сдвиге.
- Produces: `class BlpocMatcher(Matcher)`; `name = "blpoc"`; параметры `from_config(path)`; `enroll(touches)` отбирает до 12 фрагментов: качество и покрытие выше порогов, корреляция с уже взятыми ниже `t_novel`; `score` - максимум `psr` по фрагментам при `overlap_fraction >= min_overlap`, `None` для пустого или слабого кадра (`coverage < t_cov` или `quality < t_q`).

- [ ] **Step 1: Тесты по частям (каждый сначала FAIL):**
  - `test_prepare_zero_mean_unit_variance` (на синтетической синусоидальной текстуре), `test_prepare_empty_returns_none`;
  - `test_coverage_full_vs_half` (полная текстура -> выше 0.9, текстура на половине кадра -> между 0.4 и 0.6, плоский кадр -> 0.0), `test_quality_orders_contrast` (контрастная выше слабой);
  - `test_blpoc_recovers_shift` (текстура сдвинута на `(3, -5)` -> `(dy, dx)` совпадает по модулю, `psr` выше порога из конфига), `test_blpoc_unrelated_has_low_psr`;
  - `test_best_over_rotations_finds_angle` (поворот на 8 градусов -> найден угол в пределах 2 градусов);
  - `test_overlap_fraction_small_for_large_shift`, `test_matcher_rejects_low_overlap`;
  - `test_matcher_empty_frame_returns_none`, `test_enroll_prefers_diverse_patches` (дубли одного фрагмента не берутся).
- [ ] **Step 2: Реализовать функции по очереди, после каждой запускать соответствующие тесты до PASS.**
- [ ] **Step 3: Первый запуск на `dev`: `python -m lab.run_eval --matcher blpoc --protocol varied->natural --split dev`; результат не подбирать, только зафиксировать.**
- [ ] **Step 4: Commit.**

### Task 12: Подбор параметров на «разработке» и итоговая оценка

**Files:**
- Create: `lab/tune.py`, `reports/m2-gate.md`, `tests/test_tune.py`
- Modify: `lab/matchers/blpoc_config.json`

**Interfaces:**
- Produces: `tune(matcher_factory, dataset_dev, grid: dict[str, Sequence], protocols: Sequence[str]) -> dict` - перебор сетки (полоса `(0.05, 0.42)` и `(0.05, 0.5)`; `sigma` 3-5; `t_cov`, `t_q`, `t_novel`, `min_overlap`; углы `±20` шагом 4); цель - максимизировать `normalized_gap`, при равенстве минимизировать `frr_far0`; принимает **только** касания из `dev` (`HoldoutGuard`).
- Produces: `run_holdout_once(matchers, holdout, lock_path: Path, force: bool = False) -> list[Report]` - создаёт файл-замок; второй запуск без `force=True` бросает `HoldoutAlreadyUsed`.

- [ ] **Step 1: Тесты:** `test_tune_rejects_holdout_touches` (передать отложенное -> `HoldoutLeakError`), `test_tune_picks_best_gap` (маленькая сетка на синтетике), `test_holdout_runs_once` (второй вызов -> `HoldoutAlreadyUsed`).
- [ ] **Step 2: FAIL -> реализовать -> PASS.**
- [ ] **Step 3: Запустить `tune` на `dev`, записать выбранные значения в `blpoc_config.json`, закоммитить конфиг до касания отложенных данных.**
- [ ] **Step 4: Выполнить `run_holdout_once` для `openchicago`, `sift-pairwise`, `blpoc` по обоим протоколам.**
- [ ] **Step 5: Записать `reports/m2-gate.md`:** таблица метрик с доверительными интервалами, оговорки о размере набора и вердикт по критерию: **PASS** (B не хуже `openchicago` по FRR@FAR0 и по зазору, с учётом интервалов), **FAIL** (иначе). Вердикт и дальнейший путь (M4 или кандидат C или остановка) предлагает ассистент, **решение принимает пользователь**.
- [ ] **Step 6: Commit.**

### Task 13: Отчёт этапа в репозитории заметок

**Files:**
- Create: `docs/stage1-report.md` и `docs/stage1-report.ru.md` в `~/src/goodix-27c6-5125-honor-magicbook`

- [ ] **Step 1: Перенести из `reports/` только агрегированные числа и вердикт (без кадров и без путей к личным данным).**
- [ ] **Step 2: Прогнать поиск личных данных (как раньше) и закоммитить локально; отправка на GitHub по разрешению пользователя.**
