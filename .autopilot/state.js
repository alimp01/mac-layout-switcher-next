window.STATE =
{
  "slug": "mac-layout-switcher",
  "dir": "2026-08-29-mac-layout-switcher",
  "title": "Mac Layout Switcher Next — Keyboop fork",
  "mode": "semi",
  "depth": "normal",
  "polish": null,
  "tier": "T2",
  "briefFile": "2026-08-29-brief.md",
  "memoryFile": "CLAUDE.md",
  "skillDir": "/home/claudebot/.claude/skills/autopilot",
  "startedAt": "2026-08-29T03:22:57+00:00",
  "updatedAt": "2026-11-06",
  "stages": [
    {
      "id": "preflight",
      "status": "done",
      "startedAt": "2026-08-29T03:22:57+00:00",
      "finishedAt": "2026-08-29T03:24:41+00:00"
    },
    {
      "id": "manifest",
      "status": "done",
      "startedAt": "2026-08-29T03:24:41+00:00",
      "finishedAt": "2026-08-29T03:27:10+00:00"
    },
    {
      "id": "briefing",
      "status": "done",
      "startedAt": "2026-08-29T03:27:10+00:00",
      "finishedAt": "2026-08-29T03:34:30+00:00"
    },
    {
      "id": "spec",
      "status": "done",
      "startedAt": "2026-08-29T03:34:30+00:00",
      "finishedAt": "2026-08-29T03:44:20+00:00"
    },
    {
      "id": "plan",
      "status": "done",
      "startedAt": "2026-08-29T03:44:20+00:00",
      "finishedAt": "2026-08-29T03:52:30+00:00",
      "note": "23 тикета; дополнение G20 2026-10-08"
    },
    {
      "id": "build",
      "status": "active",
      "startedAt": "2026-08-29T03:52:30+00:00",
      "note": "G29/T34 complete:1.4.12 published and actual Spotlight Option accepted by user27.10. G27 Codex/G28 Bitrix scoped acceptances retained; other historical scopes unchanged."
    },
    {
      "id": "review",
      "status": "pending",
      "startedAt": "2026-10-08T04:45:11.080956+00:00",
      "note": "G29/T34 complete:1.4.12 published and actual Spotlight Option accepted by user27.10. G27 Codex/G28 Bitrix scoped acceptances retained; other historical scopes unchanged."
    },
    {
      "id": "final",
      "status": "pending",
      "startedAt": "2026-08-29T05:25:00+00:00",
      "note": "G29/T34 complete:1.4.12 published and actual Spotlight Option accepted by user27.10. G27 Codex/G28 Bitrix scoped acceptances retained; other historical scopes unchanged."
    }
  ],
  "requirements": {
    "total": 39,
    "done": 35,
    "inTicket": 3,
    "droppedNote": "G07 отменён пользователем в пользу G08",
    "inSpec": 0,
    "placeholder": 0,
    "deferred": 0,
    "dropped": 1
  },
  "tickets": [
    {
      "id": "01",
      "title": "Каркас SwiftPM + ядро: KeyMap, WordBuffer, SnippetStore",
      "requirements": [
        "R02",
        "R03",
        "R07i",
        "G01"
      ],
      "blockedBy": [],
      "wave": 1,
      "zone": [
        "Package.swift",
        "Sources/SwitcherCore/",
        "Tests/"
      ],
      "status": "done",
      "startedAt": "2026-08-29T03:56:00+00:00",
      "finishedAt": "2026-08-29T04:12:40+00:00",
      "tests": {
        "passed": 12,
        "failed": 0
      },
      "commit": "8ee81d5",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "02",
      "title": "Детектор неправильной раскладки",
      "requirements": [
        "R04i"
      ],
      "blockedBy": [
        "01"
      ],
      "wave": 2,
      "zone": [
        "Sources/SwitcherCore/Detector"
      ],
      "status": "done",
      "startedAt": "2026-08-29T04:13:20+00:00",
      "finishedAt": "2026-08-29T04:42:00+00:00",
      "tests": {
        "passed": 17,
        "failed": 0
      },
      "commit": "59f0216",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "03",
      "title": "Системный слой macOS: перехват, перепечатка, раскладка",
      "requirements": [
        "R06i",
        "R03"
      ],
      "blockedBy": [
        "01"
      ],
      "wave": 2,
      "zone": [
        "Sources/MacLayoutSwitcher/System/"
      ],
      "status": "done",
      "startedAt": "2026-08-29T04:13:20+00:00",
      "finishedAt": "2026-08-29T04:32:10+00:00",
      "tests": {
        "passed": 12,
        "failed": 0
      },
      "commit": "54da5e2",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "04",
      "title": "Engine: автоисправление, Option, откат, автозамена, автопауза",
      "requirements": [
        "R04i",
        "R05i",
        "G01",
        "A01"
      ],
      "blockedBy": [
        "02",
        "03"
      ],
      "wave": 3,
      "zone": [
        "Sources/MacLayoutSwitcher/Engine",
        "Sources/MacLayoutSwitcher/Config"
      ],
      "status": "done",
      "startedAt": "2026-08-29T04:42:30+00:00",
      "finishedAt": "2026-08-29T04:53:00+00:00",
      "tests": {
        "passed": 28,
        "failed": 0
      },
      "commit": "2a2f260",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "05",
      "title": "Меню-бар, звуки, сборка .app, README",
      "requirements": [
        "R06i",
        "G02",
        "R07i",
        "R01"
      ],
      "blockedBy": [
        "04"
      ],
      "wave": 4,
      "zone": [
        "Sources/MacLayoutSwitcher/UI/",
        "build.sh",
        "README.md"
      ],
      "status": "done",
      "startedAt": "2026-08-29T04:53:30+00:00",
      "finishedAt": "2026-08-29T05:24:00+00:00",
      "tests": {
        "passed": 28,
        "failed": 0
      },
      "commit": "272742e",
      "retries": 0,
      "repairs": 1,
      "repairFindings": [
        "звук клика играл в secure input/паузе — нарушение A01 «молчать полностью»"
      ],
      "handoffs": 0
    },
    {
      "id": "06",
      "title": "Порог отмен перед авто-исключением",
      "requirements": [
        "G03"
      ],
      "blockedBy": [
        "04"
      ],
      "wave": 5,
      "zone": [
        "Sources/SwitcherCore/EngineCore",
        "Sources/MacLayoutSwitcher/Config",
        "Sources/MacLayoutSwitcher/Engine"
      ],
      "status": "done",
      "startedAt": "2026-08-29T06:50:00+00:00",
      "finishedAt": "2026-08-29T07:05:00+00:00",
      "tests": {
        "passed": 31,
        "failed": 0
      },
      "commit": "6df8775",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "07",
      "title": "Упаковка в .dmg-дистрибутив",
      "requirements": [
        "G04"
      ],
      "blockedBy": [
        "05"
      ],
      "wave": 5,
      "zone": [
        "build-dmg.sh",
        "build.sh",
        "README.md"
      ],
      "status": "done",
      "startedAt": "2026-08-29T06:58:00+00:00",
      "finishedAt": "2026-08-29T07:20:00+00:00",
      "tests": {
        "passed": 31,
        "failed": 0
      },
      "commit": "5f5ebc1",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "08",
      "title": "Настройка горячих клавиш",
      "requirements": [
        "G05"
      ],
      "blockedBy": [
        "04",
        "06"
      ],
      "wave": 6,
      "zone": [
        "Sources/SwitcherCore/Hotkey",
        "Sources/SwitcherCore/EngineCore",
        "Sources/MacLayoutSwitcher/Config",
        "Sources/MacLayoutSwitcher/Engine",
        "Sources/MacLayoutSwitcher/UI/"
      ],
      "status": "done",
      "startedAt": "2026-08-29T07:12:00+00:00",
      "finishedAt": "2026-08-29T07:35:00+00:00",
      "tests": {
        "passed": 43,
        "failed": 0
      },
      "commit": "9754eb0",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "09",
      "title": "Автозапуск при входе (launch at login)",
      "requirements": [
        "G06"
      ],
      "blockedBy": [
        "05",
        "08"
      ],
      "wave": 7,
      "zone": [
        "Sources/MacLayoutSwitcher/System/LoginItem",
        "Sources/MacLayoutSwitcher/Config",
        "Sources/MacLayoutSwitcher/UI/StatusBarUI",
        "Sources/MacLayoutSwitcher/main.swift"
      ],
      "status": "done",
      "startedAt": "2026-08-31T09:00:00+00:00",
      "finishedAt": "2026-08-31T09:20:00+00:00",
      "tests": {
        "passed": 43,
        "failed": 0
      },
      "commit": "21f8a6b",
      "retries": 0,
      "repairs": 1,
      "repairFindings": [
        "register→.requiresApproval снимал галочку без подсказки — пользователь видит «не работает»"
      ],
      "handoffs": 0
    },
    {
      "id": "10",
      "title": "Инфраструктура иконки (.icns в бандле)",
      "requirements": [
        "G08"
      ],
      "blockedBy": [
        "05",
        "07"
      ],
      "wave": 8,
      "zone": [
        "Resources/",
        "tools/make-icns.py",
        "build.sh"
      ],
      "status": "done",
      "startedAt": "2026-08-31T10:10:00+00:00",
      "finishedAt": "2026-08-31T10:40:00+00:00",
      "tests": {
        "passed": 43,
        "failed": 0
      },
      "commit": "f4a2248",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "11",
      "title": "Утка-иконка + индикация раскладки в трее",
      "requirements": [
        "G08",
        "G09"
      ],
      "blockedBy": [
        "10"
      ],
      "wave": 9,
      "zone": [
        "Resources/AppIcon.icns",
        "Sources/MacLayoutSwitcher/UI/",
        "Sources/MacLayoutSwitcher/main.swift"
      ],
      "status": "done",
      "startedAt": "2026-08-31T10:40:00+00:00",
      "finishedAt": "2026-08-31T11:30:00+00:00",
      "tests": {
        "passed": 43,
        "failed": 0
      },
      "commit": "6fdee31",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "12",
      "title": "Звук только на исправление",
      "requirements": [
        "G10"
      ],
      "blockedBy": [
        "11"
      ],
      "wave": 10,
      "zone": [
        "Sources/MacLayoutSwitcher/Engine.swift",
        "Sources/MacLayoutSwitcher/UI/Sounds.swift"
      ],
      "status": "done",
      "startedAt": "2026-08-31T12:05:00+00:00",
      "finishedAt": "2026-08-31T12:25:00+00:00",
      "tests": {
        "passed": 43,
        "failed": 0
      },
      "commit": "30b02db",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "13",
      "title": "Автообновление через GitHub",
      "requirements": [
        "G11"
      ],
      "blockedBy": [
        "11"
      ],
      "wave": 11,
      "zone": [
        "VERSION",
        "Sources/MacLayoutSwitcher/System/Updater",
        "tools/self-update.sh",
        "build.sh"
      ],
      "status": "done",
      "startedAt": "2026-08-31T12:50:00+00:00",
      "finishedAt": "2026-08-31T13:40:00+00:00",
      "tests": {
        "passed": 49,
        "failed": 0
      },
      "commit": "e73a751",
      "retries": 0,
      "repairs": 1,
      "repairFindings": [
        "rm -rf без гарда .app + предложение обновления вне бандла = снос произвольного каталога; interactive-офлайн молчит; замена не атомарна"
      ],
      "handoffs": 0
    },
    {
      "id": "14",
      "title": "Исправление ДО доставки разделителя (активный EventTap)",
      "requirements": [
        "G12"
      ],
      "blockedBy": [
        "13"
      ],
      "wave": 12,
      "zone": [
        "Sources/SwitcherCore/EngineCore",
        "Sources/MacLayoutSwitcher/System/EventTap",
        "Sources/MacLayoutSwitcher/System/Typist",
        "Sources/MacLayoutSwitcher/Engine"
      ],
      "status": "done",
      "startedAt": "2026-09-15T12:20:00+00:00",
      "finishedAt": "2026-09-15T15:10:00+00:00",
      "tests": {
        "passed": 58,
        "failed": 0
      },
      "commit": "3b51c43",
      "retries": 0,
      "repairs": 1,
      "repairFindings": [
        "typeKey молча терял подавленный Enter; гонка ввода во время перепечатки; файловый I/O в колбэке активного tap'а; мёртвый then:"
      ],
      "handoffs": 0
    },
    {
      "id": "15",
      "title": "Короткие частотные слова: «Как», «ты», «и»",
      "requirements": [
        "G13"
      ],
      "blockedBy": [
        "02"
      ],
      "wave": 12,
      "zone": [
        "Sources/SwitcherCore/Detector",
        "Sources/SwitcherCore/ShortWords"
      ],
      "status": "done",
      "startedAt": "2026-09-15T13:10:00+00:00",
      "finishedAt": "2026-09-15T15:10:00+00:00",
      "tests": {
        "passed": 58,
        "failed": 0
      },
      "commit": "3b51c43",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0
    },
    {
      "id": "16",
      "title": "Локальная расшифровка WAV через GigaAM v3",
      "requirements": [
        "G14"
      ],
      "blockedBy": [],
      "wave": 13,
      "status": "done",
      "commit": "9a83348",
      "retries": 0,
      "repairs": 0,
      "handoffs": 0,
      "finishedAt": "2026-09-16T03:13:27.206206+00:00",
      "tests": {
        "passed": 71,
        "failed": 0
      }
    },
    {
      "id": "17",
      "title": "Диктовка по удержанию горячей клавиши и вставка в поле",
      "requirements": [
        "G14"
      ],
      "blockedBy": [
        "16"
      ],
      "wave": 14,
      "status": "done",
      "commit": "0b378f3",
      "retries": 0,
      "repairs": 1,
      "handoffs": 0,
      "finishedAt": "2026-09-16T03:13:27.206206+00:00",
      "tests": {
        "passed": 71,
        "failed": 0
      },
      "repairFindings": [
        "P2: потерянный keyUp после паузы/записи хоткея мог съесть первый Space; полный reset жеста и подавленных клавиш, 2 регрессионных теста"
      ]
    },
    {
      "id": "18",
      "title": "Целостность ввода и одиночные и/я",
      "requirements": [
        "G15"
      ],
      "blockedBy": [],
      "status": "done",
      "wave": 15,
      "commit": "321eba8",
      "validation": "36 focused Linux tests passed; Mac build passed; both reviewers approved after repairs",
      "repairs": 1
    },
    {
      "id": "19",
      "title": "Автоматическая подготовка модели",
      "requirements": [
        "G16"
      ],
      "blockedBy": [],
      "status": "done",
      "wave": 15,
      "commit": "2bb8f1f",
      "validation": "Native real model cache/restarts/download/cancel/offline PASS; Spec+Standards no findings"
    },
    {
      "id": "20",
      "title": "Конвертация выделенного текста",
      "requirements": [
        "G17"
      ],
      "blockedBy": [
        "18"
      ],
      "status": "done",
      "wave": 16,
      "commit": "12cc6de",
      "tests": {
        "passed": 85,
        "failed": 0
      },
      "validation": "Native debug + integrated Spec/Standards approved; live AX acceptance pending"
    },
    {
      "id": "21",
      "title": "Системная полнота исправлений и защита правильных слов",
      "requirements": [
        "G18"
      ],
      "blockedBy": [],
      "status": "done",
      "wave": 17,
      "commit": "fec1515",
      "finishedAt": "2026-10-07T07:44:01.810778+00:00",
      "tests": {
        "passed": 95,
        "failed": 0
      },
      "validation": "49 targeted tests;95 fullLinux; two independent approvals; frozen audit; native release/DMG verification"
    },
    {
      "id": "22",
      "title": "Вставка диктовки и видимый результат",
      "requirements": [
        "G19"
      ],
      "blockedBy": [],
      "wave": 18,
      "status": "done",
      "commit": "e857996",
      "finishedAt": "2026-10-08T04:32:25.996828+00:00",
      "tests": {
        "passed": 95,
        "failed": 0
      },
      "validation": "Native panel red/green and adapter pass independently; actual Codex routing metadata; fullLinux95; both reviews approved; release/DMG verified",
      "repairs": 1
    },
    {
      "id": "23",
      "title": "Восстановить Option и автоматическую замену",
      "requirements": [
        "G20"
      ],
      "status": "done",
      "blockedBy": [],
      "wave": 19,
      "zone": [
        "Sources/MacLayoutSwitcher",
        "Tests",
        "tools"
      ],
      "retries": 0,
      "repairs": 0,
      "handoffs": 0,
      "startedAt": "2026-10-08T04:39:46.121007+00:00",
      "finishedAt": "2026-10-08T05:54:58.892222+00:00",
      "commit": "d7b003d",
      "tests": {
        "passed": 95,
        "failed": 0
      },
      "review": {
        "spec": "approved",
        "standards": "approved"
      }
    },
    {
      "id": "24",
      "title": "Исправить удаление вместо замены",
      "requirements": [
        "G21"
      ],
      "status": "done",
      "startedAt": "2026-10-10T09:26:43.132471+00:00",
      "blockedBy": [],
      "wave": 20,
      "zone": [
        "Sources/MacLayoutSwitcher",
        "tools"
      ],
      "retries": 0,
      "repairs": 0,
      "handoffs": 1,
      "partialCommit": "c57e700f9f44f62dd79d2576e88300d994932ccb",
      "validation": "Frozen160 checksum exact; same finalrunner baselineRED finalGREEN; root+2independentreviewers engine/native/G19PASS; rootfullspeech+Linux95PASS",
      "tests": {
        "passed": 95,
        "failed": 0
      },
      "review": {
        "spec": "approved",
        "standards": "approved",
        "scope": "Concrete autorepeat race; physicaluser/crossprocess delivery unverified"
      },
      "note": "Allapps autoSpace/Enter trigger known; scoped fix approved; manual acceptance pending",
      "finishedAt": "2026-10-10T14:37:25.105000+00:00"
    },
    {
      "id": "25",
      "title": "Исправить реальное удаление после1.4.4",
      "requirements": [
        "G22"
      ],
      "status": "done",
      "startedAt": "2026-10-10T15:15:18.569320+00:00",
      "blockedBy": [],
      "zone": [
        "Sources/MacLayoutSwitcher",
        "tools"
      ],
      "wave": 21,
      "validation": "Concrete delayedACK baselineRED/finalGREEN; root nativeEngine+delay/G19/fullspeech/Linux95; Spec+Standards finalapproved; installedphysicalSpace GREEN bothownedCodexfields",
      "candidateCodeCommit": "2163e0a3e7fa7f388ba551ef97b69d9a6f0a3126",
      "reviews": "Both finalapproved0blockers",
      "finishedAt": "2026-10-10T16:23:10.954219+00:00",
      "commit": "2163e0a3e7fa7f388ba551ef97b69d9a6f0a3126"
    },
    {
      "id": "26",
      "title": "Полная вставка диктовки после1.4.5",
      "requirements": [
        "G23"
      ],
      "status": "done",
      "startedAt": "2026-10-10T16:32:38.436837+00:00",
      "blockedBy": [],
      "zone": [
        "Sources/MacLayoutSwitcher/Speech",
        "tools"
      ],
      "wave": 22,
      "validation": "LiteralbaselineRED16; concurrentforeign/multiOwn/capacitywait RED→GREEN; rootfinal15groups/Engine/delay/nativefullspeech/mountedDMG; exact27file Linux95reuse; actualspeech pending",
      "repairs": 3,
      "review": {
        "spec": "approved",
        "standards": "approved",
        "sourceSHA256": "cf3d4d6e29672b1c9601e0cd4234c9253ee94d3214d45f428a65f9429d351c41",
        "findings": 0
      },
      "tests": {
        "passed": 95,
        "failed": 0,
        "nativeCompletionGroups": 15
      },
      "commit": "f96f920104b538201d12c51bf7d8d8018eaf5b71",
      "finishedAt": "2026-10-10T17:27:38.248052+00:00"
    },
    {
      "id": "27",
      "title": "Исправить замену в Safari",
      "requirements": [
        "G24"
      ],
      "status": "in-progress",
      "startedAt": "2026-10-11T18:02:46.082222+00:00",
      "blockedBy": [],
      "wave": 23,
      "repairs": 0,
      "note": "1.4.7 installed/published. 2reviews/native/Linux95/DMG/public80hashes PASS. User permissions and physical Safari pending.",
      "commit": "4297eef1bb3dcce48604e7ff789c462aec64acfd"
    },
    {
      "id": "28",
      "title": "Конвертация по Option: отказ захвата в Codex",
      "requirements": [
        "G25"
      ],
      "blockedBy": [],
      "wave": 24,
      "zone": [
        "Engine",
        "SelectionConverter",
        "InputFocusGuard",
        "platform adapter",
        "native harness"
      ],
      "status": "in-progress",
      "startedAt": "2026-10-23T08:03:24.375733+00:00",
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "tests": {
        "passed": 95,
        "failed": 0
      },
      "validation": "two reviews approved0; native7/Linux95/fullspeech/mountedDMG/installed1.4.8 exact/publicarchive91hashes PASS; user launch/Option acceptance pending",
      "version": "1.4.8",
      "commit": "3f4f8166971c2ee1468b209f234351deea6b801a",
      "publication": "1.4.8 verified; code3f4f816; metadata receipt follows",
      "actualAcceptance": "FAILED25.10: unavailableField on ghbdtn/Option; continuesG26/T29"
    },
    {
      "id": "29",
      "title": "Системный поиск поля и проверка надёжности всего приложения",
      "requirements": [
        "G26"
      ],
      "blockedBy": [],
      "wave": 25,
      "status": "in-progress",
      "startedAt": "2026-10-25T05:11:39.865636+00:00",
      "retries": 0,
      "repairs": 0,
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "version": "1.4.9",
      "validation": "Final integrated suites and exact99hashes reviewed; see audit/reliability",
      "actualAcceptance": "pending separate physical keyboard check",
      "commit": "b7759822fc16796ee3fc8b05dfa9bae967322b3a",
      "publication": "1.4.9 code45d6221 public archive verified"
    },
    {
      "id": "30",
      "title": "Целостность физического ввода и восстановление EventTap",
      "requirements": [
        "G26"
      ],
      "blockedBy": [],
      "wave": 25,
      "status": "done",
      "retries": 0,
      "repairs": 0,
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "version": "1.4.9",
      "validation": "Final integrated suites and exact99hashes reviewed; see audit/reliability",
      "actualAcceptance": "pending separate physical keyboard check",
      "commit": "1519f6001f60017bd0272abf98f0cf9e8d2bfb70",
      "publication": "1.4.9 code45d6221 public archive verified"
    },
    {
      "id": "31",
      "title": "Восстановление после ошибки обновления и возобновления",
      "requirements": [
        "G26"
      ],
      "blockedBy": [],
      "wave": 26,
      "status": "done",
      "retries": 0,
      "repairs": 0,
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "version": "1.4.9",
      "validation": "Final integrated suites and exact99hashes reviewed; see audit/reliability",
      "actualAcceptance": "pending separate physical keyboard check",
      "commit": "45d622165d10699b7f058c1ae7d9b289dc20b711",
      "publication": "1.4.9 code45d6221 public archive verified"
    },
    {
      "id": "32",
      "title": "Захват поля при AX noValue",
      "requirements": [
        "G27"
      ],
      "status": "done",
      "blockedBy": [],
      "wave": 27,
      "repairs": 0,
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "validation": "baseline RED13 → final raw GREEN77; adapters; fullspeech; mountedDMG; exact Linux95 reuse; user confirmed physical ghbdtn+Option and ghbdtn+Space in Codex",
      "commit": "72c48b6af12d85e0da244fc55285e00d3fe446f7",
      "finishedAt": "2026-10-25T07:07:12.141278+00:00",
      "physicalAcceptance": "passed",
      "acceptedAt": "2026-10-25T12:24:37.905378+00:00"
    },
    {
      "id": "33",
      "title": "Поддержка Битрикс24 и Яндекса",
      "requirements": [
        "G28"
      ],
      "status": "done",
      "blockedBy": [],
      "wave": 28,
      "review": {
        "spec": "approved",
        "standards": "approved"
      },
      "validation": "Same final raw RED24→GREEN147, adapters, Linux95 exact27 reuse, fullspeech/mountedDMG; physical Bitrix Option accepted by user",
      "commit": "77e96bec6ce1a54f4d8c624b202fa0bfeb670621",
      "finishedAt": "2026-10-26T07:13:05.380626+00:00",
      "acceptedAt": "2026-10-26T09:36:58.857391+00:00",
      "physicalAcceptance": "passed: Bitrix24 Option"
    },
    {
      "id": "34",
      "title": "Конвертация в системном Spotlight",
      "requirements": [
        "G29"
      ],
      "blockedBy": [],
      "status": "done",
      "startedAt": "2026-10-26T15:46:18.533238+00:00",
      "zone": [
        "shared AX focus capture",
        "keyboard/dictation targets",
        "native harnesses"
      ],
      "retries": 0,
      "repairs": 2,
      "handoffs": 0,
      "implementation": "complete",
      "reviews": "Spec/Standards final approved0",
      "validation": "raw199/adapters20+2/Option7+7/rootEngine27/exactLinux95/fullspeech/DMG PASS",
      "physicalAcceptance": "passed: actual Spotlight ghbdtn+Option → привет, user confirmed",
      "commit": "dba351ccdd82cd737661531e744dc0bd2c5b33e7",
      "publication": "verified",
      "finishedAt": "2026-10-27T03:23:04.365606+00:00",
      "acceptedAt": "2026-10-27T03:23:04.365606+00:00"
    },
    {
      "id": "35",
      "title": "Separate Next identity",
      "requirements": [
        "G30"
      ],
      "status": "done",
      "blockedBy": [],
      "tests": {
        "updaterCases": 23,
        "identity": "pass",
        "packaging": "pass",
        "resume": "pass",
        "nativeBuild": "speech-disabled pass"
      },
      "standardsReview": "scoped approved0; identity/packaging/updater23 independently passed",
      "specReview": "scoped product approved0; active README integration P2 belongs final T37",
      "review": "Spec + Standards scoped approved",
      "commit": "31d71a7"
    },
    {
      "id": "36",
      "title": "Keyboop language detection",
      "requirements": [
        "G31"
      ],
      "status": "done",
      "blockedBy": [],
      "nativeTests": {
        "methods": 103,
        "assertions": 4564,
        "failed": 0,
        "kind": "supplemental adapter; true Linux XCTest pending"
      },
      "specReview": "scoped product approved0",
      "tests": {
        "passed": 103,
        "failed": 0,
        "runtime": "Linux XCTest exact public3735b80"
      },
      "standardsReview": "scoped approved0",
      "review": "Spec + Standards scoped approved",
      "commit": "3735b80"
    },
    {
      "id": "37",
      "title": "Keyboop replacement transport",
      "requirements": [
        "G32"
      ],
      "status": "done",
      "blockedBy": [
        "35",
        "36"
      ],
      "note": "Next1.5.0 published/installed; user confirmed Codex ghbdtn+Space and ghbdtn+Option on2026-11-06",
      "commit": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f",
      "review": "Spec APPROVE0 + Standards APPROVE0",
      "tests": {
        "passed": 110,
        "failed": 0
      }
    }
  ],
  "singlePass": null,
  "tests": {
    "passed": 110,
    "failed": 0,
    "runtime": "Linux XCTest",
    "commit": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f",
    "note": "Linux110 and native/build/DMG PASS; user confirmed Codex physical Space and Option on2026-11-06; other physical paths untested"
  },
  "debt": {
    "placeholders": [],
    "assumptions": [],
    "emptyEnv": []
  },
  "additions": [
    {
      "id": "G14",
      "title": "Локальная диктовка по удержанию хоткея, GigaAM v3",
      "status": "done",
      "tickets": [
        "16",
        "17"
      ]
    },
    {
      "id": "G15",
      "title": "Целостность ввода и одиночные и/я",
      "status": "done",
      "tickets": [
        "18"
      ]
    },
    {
      "id": "G16",
      "title": "Автоматическая подготовка модели",
      "status": "done",
      "tickets": [
        "19"
      ]
    },
    {
      "id": "G17",
      "title": "Конвертация выделенного текста",
      "status": "done",
      "tickets": [
        "20"
      ]
    },
    {
      "id": "G18",
      "title": "Системный аудит замен",
      "status": "done",
      "tickets": [
        "21"
      ]
    },
    {
      "id": "G19",
      "title": "Исправить вставку диктовки",
      "status": "done",
      "tickets": [
        "22"
      ]
    }
  ],
  "coverage": {
    "findings": 0,
    "note": "G2: пропусков нет, полупокрытий нет; 8 позиций «сверх брифа» = R##.n-проработка и A01 с родителем — оставлены"
  },
  "concerns": [
    "Tests/SwitcherCoreTests/*:2 — @testable import SwitcherCore, хотя ассерты ходят через публичный шов; условие: обычный import",
    "РЕШЕНО в T04: EventTap оставлен .listenOnly осознанно — исправление стирает слово вместе с уже напечатанным разделителем и перепечатывает; подавлять нечего. Плата: Enter-как-submit в chat-полях может перепечататься (задокументировано в Engine.swift). Ревью 04 признало переигровкой, не блок.",
    "Typist.swift:50,68 — отказ создания CGEvent молча съедает событие, частичная замена портит текст; условие: прерывать весь replaceLastWord",
    "Typist.swift:27 — 5000 мкс на событие ≈0.2 с на слово; условие: обосновать или уменьшить",
    "DetectorTests.swift:90,102 — ambiguousShort все <3 символов, дублируют testShortMixed; условие: спорные короткие ≥3 либо убрать метку",
    "Detector.swift:167 — save глотает ошибку записи через try? молча; условие: не выглядеть успехом при отказе или задокументировать",
    "Config.swift:100 — при тихом провале move битого config следующий save() затрёт оригинал дефолтами, .broken-бэкап не останется; условие: бэкап копией до записи либо не затирать при неудаче",
    "EngineCore.swift:237 — cyrillicSet дублирует алфавит из Detector/KeyMap (3-е место); условие: единый источник, если появится публичный шов классификатора",
    "EngineCoreTests.swift:3 — @testable import избыточен (ассерты через публичный шов); условие: обычный import",
    "main.swift:83,162 — openInEditor и relaunch глотают отказ через try? молча; условие: отказ не должен выглядеть успехом",
    "T10 make-icns.py:104 — self-check делит константу CHUNK_TYPES со сборщиком (самоподтверждение в миниатюре); условие: эталон типов отдельным литералом",
    "T11 main.swift:134 — имя TIS-уведомления захардкожено строкой при доступной Carbon-константе; условие: kTISNotifySelectedKeyboardInputSourceChanged as String",
    "T11 main.swift:29+StatusBarUI:56 — факт ручной паузы дублирован (manualPaused и state.paused, OR прячет рассинхрон); условие: единый источник",
    "T06 EngineCore/Engine — при пороге счётчик пишется key=0, а не удаляется; undo-counts.json монотонно пухнет мёртвыми записями; условие: удалять сброшенный ключ",
    "T06 EngineCore — дефолт undoThreshold=3 нигде не проверяется тестом без явной передачи порога; условие: тест на конструктор без порога",
    "T14 Engine.swift:383 / Typist.keyCode(forSeparator:) — запасной путь по символу недостижим (stroke==nil только у хоткеев); условие: убрать или сделать stroke обязательным для boundary",
    "T14 Detector.save(to:) — приложением больше не используется (персист через Config.saveExclusions), жив только в тестах; условие: одна точка записи exclusions.json",
    "T14 Engine.swift:172 — isBusy = «очередь пуста», а не «события доставлены»: микроокно после последней синтетики; условие: зафиксировать как известную плату",
    "T14 EventTap mask — реальный keyUp разделителя не подавляется (mask keyDown+flagsChanged): приложение видит одиночный keyUp после синтетической пары; для текстовых полей безвредно; условие: зафиксировать как известную плату / подавлять парный keyUp",
    "T14 Typist.replaceLastWord(then:) добавлен, Engine не использует (порядок через typeKey в той же очереди); условие: убрать неиспользуемый параметр",
    "T09 StatusBarUI:23 — State.launchAtLogin имеет дефолт =false, прочие поля нет; условие: убрать дефолт или задать всем",
    "T09: CLAUDE.md не упоминает launchAtLogin/LoginItem.swift; условие: дописать при финале памяти",
    "CLAUDE.md устарел: «28 тестов» (стало 43) + раздел Архитектура упоминает InputEvent.optionTap (переименован в .hotkey(.convert)); условие: обновить память при финале",
    "T08 Hotkey.swift — rightCommand/rightOption/... в модели, но не порождаются (Engine и рекордер схлопывают лево/право); speculative generality; условие: либо различать, либо убрать кейсы",
    "T08 HotkeyRecorderWindow — рекордер записывает голый печатный keyDown (напр. «K»), который под .listenOnly и сработает, и напечатается; условие: отклонять/предупреждать голый печатный keyCode",
    "T08 HotkeyTests/HotkeyEngineTests — @testable import избыточен; условие: обычный import",
    "2026-09-16: baseline swift build успешен на macOS15.6.1 arm64; swift test на Mac blocked: CLT без XCTest. Тесты выполнять на доступном claudebot-server (Swift6.0.3). v1.2.0 ручная приёмка ещё не выполнена.",
    "G21 historical:1.4.4 actualuserdeletion FAILED; ownTextEdit fixture closed; continuedG22.",
    "G22:1.4.5 actualownedCodexSpaceGREEN bothfields, matching concrete delayedACK fix; privatecomposer/allapps/manualEnterShift untested, not universal compatibilityclaim.",
    "G23:1.4.5 actualdictation partialprefix with fullrecognized recovery; first16UTF16 clue only, previousadapter checks insufficient foractualCodexdelivery."
  ],
  "reviewers": {
    "manifestSpec": "a3373fd28e916b546",
    "craft": "a9af146a77a904cc1",
    "G14": {
      "spec": "review_spec",
      "standards": "review_standards",
      "recheck": "P2 resolved, no remaining actionable findings"
    },
    "G15-G17": {
      "spec": "review_repairs_spec",
      "standards": "review_repairs_standards",
      "result": "Both approved integrated code; last cancellation fix rechecked"
    },
    "G18": {
      "spec": "review_word_spec",
      "standards": "review_word_standards",
      "result": "Both approved finaldiff with zero actionable findings"
    },
    "G19": {
      "spec": "review_dictation_spec",
      "standards": "review_dictation_standards",
      "result": "Both final approved, no blocking findings; liveAX/CG and notification-window limitations documented"
    },
    "G21": {
      "spec": "review_autorepeat_spec",
      "standards": "review_autorepeat_standards",
      "result": "Both finalapproved;0blockers; frozen baselineRED/finalGREEN; hardware/userexactcause boundary documented"
    },
    "G22": {
      "spec": "review_live_selection_spec",
      "standards": "review_live_selection_standards",
      "result": "Both finalapproved0blockers; supplemental tools also rechecked bySpec+Standards"
    },
    "G23": {
      "spec": "review_dictation_completion_spec",
      "standards": "review_dictation_completion_standards",
      "result": "Both frozen4 finalapproved0findings; all64hashes stable; actualspeech unproven"
    },
    "G26": {
      "spec": "review_reliability_spec",
      "standards": "review_reliability_standards",
      "result": "Both approved0findings; manifestSHA dddd80c7751b8f913b693f1161c6505b0093000aedc9a342d65712899a91f4d1"
    },
    "G27": {
      "spec": "review_no_value_spec",
      "standards": "review_no_value_standards",
      "result": "Both final approved, 0 outstanding findings; manifest bf30a557698b2af3fd0eeec39f60aa92bedb517cb16ed9b91eac64b6f1a231cc"
    },
    "G28": {
      "spec": "review_browser_family_spec",
      "standards": "review_browser_family_standards",
      "result": "Both final approved 0 findings; exact manifest e0635fa95231c2118c297077d29ffc29f49e88cd1f6ef2be61b25cfb73c1f7b3"
    }
  },
  "blind": {
    "run": "G23 root15groups/Engine/delayedselection/fullspeech/mountedDMG PASS; exact27fileLinux95reuse",
    "verdict": "Concrete own-notification completion + capacitywaitguards reviewed and published1.4.6",
    "note": "ActualCodexspeech/WindowServer pending usermanualtest; no universaloratomicPASS",
    "drift": []
  },
  "manualAcceptance": {
    "version": "1.5.0",
    "status": "passed",
    "scope": "Codex: physical ghbdtn + Space and separate ghbdtn + Option without selection",
    "answer": "Оба раза получилось «привет»",
    "confirmedAt": "2026-11-06T05:47:29.988899+00:00",
    "confirmedDateMoscow": "2026-11-06",
    "note": "User enabled Next Accessibility/Input Monitoring and relaunched. Only these two physical paths are accepted; other apps, Enter, rapid typing and speech are not covered."
  },
  "release": {
    "version": "1.5.0",
    "codeCommit": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f",
    "bundleID": "space.alimp.maclayoutswitcher.next",
    "binarySHA256": "98e652ed2290c370f262cb2b8b9e84436011138d160db179883a7f29405237e2",
    "helperSHA256": "ee5e3c28a2066e355ce450a0a4fb83f2eb1766f639a2cf70161bf25f3103cc0c",
    "dmgSHA256": "170ef576e14f3b0f076f7ffbdfc3f7fc6be365e2e3a1371e0dc460be43ca3a1a",
    "dmgBytes": 12224867,
    "mountedVerified": true,
    "deepStrictVerified": true,
    "allBundledFilesCompared": true,
    "resourcesVerified": true,
    "manualAcceptance": "Codex: physical ghbdtn + Space and separate ghbdtn + Option without selection",
    "artifact": "MacLayoutSwitcherNext-1.5.0.dmg",
    "repository": "alimp01/mac-layout-switcher-next",
    "status": "published and installed; scoped physical acceptance passed",
    "publication": "Next main and separate archive; final verification receipt in workspace outputs/keyboop-fork",
    "installedPID": 75271,
    "installedPath": "/Applications/MacLayoutSwitcherNext.app"
  },
  "wordCoverageAudit": {
    "independentRU": 459,
    "independentEN": 692,
    "frozenInputRows": 2934,
    "verdicts": 8802,
    "newUndeclaredValidCorrections": 0,
    "newWrongDirections": 0,
    "intentionalNewContextualCollisionRows": 9,
    "note": "Curated diagnostics, not statistical accuracy; see word-coverage-qa.md"
  },
  "dictationInsertionAudit": {
    "panelCause": "ProductionNSTextView/textContainer width0, nonempty recognizedtext clipped",
    "nativePanel": "red→green + root/2reviewers reruns",
    "nativeAdapter": "productioncapture/insert with injectedAX/nativeNSTextView; actualCodex frameworkrouting metadata PASS",
    "liveCodex": "not exercised; diagnostic process AXIsProcessTrusted=false",
    "privacy": "No microphone, privateeditor typing, TCC forcing or automaticclipboard mutation duringdiagnostics"
  },
  "keyboardRuntimeAudit": {
    "codeCommit": "d7b003d",
    "review": "Spec+Standards approved",
    "native": "Production Target/Typist + mock AX/CG and owned NSTextView; recovery NSPanel headless",
    "scope": "Lazy capture, same-snapshot source, readback, selection RPC uncertainty, fastinput retention, Option fallback",
    "live": "Prior TextEdit/Chrome PASS withdrawn: no pre-separator source snapshot, RussianWin already active; live automatic replacement unproved",
    "coldLimit": "First separator before any AX capture passes without late correction; explicit Option may recover word"
  },
  "deletionRepairAudit": {
    "partialCommit": "c57e700f9f44f62dd79d2576e88300d994932ccb",
    "snapshot": "/tmp/mls-g21-autorepeat-final.v8tpedvg",
    "files": 160,
    "linux": "/tmp/mls-g21-tests.fKQES6",
    "cause": "RED: busy separator autorepeat reaches early reset before replay, invalidates permit and native key replaces temporary source selection",
    "transport": "Unchanged productionpostToPid; realCG/NSEvent harness injects finalpost, notWindowServerproof",
    "recovery": "Original+completeplannedreplacement+heldinput preserveduntilClose",
    "review": "Both fresh reviewers final approved, no blockers",
    "release": "1.4.4 published and installed; recording reproduces deletion; G22/T25 continues investigation",
    "currentExecutor": "implement_deletion_system",
    "manualFixture": "Owned TextEdit /tmp/MLS-Option-Test.rtf saved and closed; auto replacement not triggered by CUA, inconclusive; Mac now locked",
    "engineIntegration": {
      "snapshot": "/tmp/mls-g21-engine.wvh4ck3e",
      "result": "Executor+root independentPASS directAX+productionCGlocalUnicode Enginehandle/selection/undo/cancellation",
      "boundary": "Finalpost/frontPID/AX injected; EventTapregistration andTISstub, no physicalWindowServer proof",
      "provenance": "29sources identicalbase57f54d3; README/source-provenance/seams.patch/SHA256SUMS/run.log/root-run.log"
    },
    "autorepeatRed": {
      "snapshot": "/tmp/mls-g21-repeat.3xn__0zm",
      "result": "4/4 RED Space+Enter directAX/productionCGlocalNSEvent; source руддщ before separator",
      "boundary": "Real production EventTap.process/KeyTranslator/Engine; own NSTextView, not physical WindowServer proof"
    },
    "engineSHA256": "5a91543b9a2a92dfc0e473d6949792890b92170944a8362926cc6cd461b8c7b3",
    "productionChecks": "/tmp/mls-g21-final.8ijwtyc9",
    "finalRunner": "baselineRED/finalGREEN same savedrunner; root+2reviewers independentlyPASS"
  },
  "liveInsertionAudit": {
    "recording": "/Users/ilyaalimpiev/Desktop/Запись экрана 2026-10-10 в 17.57.37.mov",
    "evidence": "srfe→empty twice at4.6/9.6secs, nochat; installed1.4.4 freshsingleprocess",
    "cause": "ACK-before-apply selection readback returns stale caret; old untouched replays separator against late source selection. Contract baselineRED plus matching actualownedCodexevent trace.",
    "ticket": "25",
    "liveProbe": "Native human srfe→chat PASS; ownedCodexIAB physical srfe→space deletionRED, valid V2log27events",
    "blocker": "none for completed scopedG22 release; supplementalmanualEnter/Shift question pending",
    "productChange": "Candidate1.4.5 bounded selectionconfirmation + unconfirmedSelection queue hold/recovery; public remains1.4.4",
    "qa": ".autopilot/2026-08-29-mac-layout-switcher/live-insertion-qa.md",
    "candidateScratch": "/var/folders/s7/blf5jdcs7q7bfjjxbt621w500000gn/T/mls-g22-candidate.zaw8onaw",
    "linux": "/tmp/mls-g22-linux.HdVgbk/run.log",
    "rootSelectionDelay": "/tmp/mls-keyboard-selection-delay.2TBufd/run.log",
    "hardwareExcerptSHA256": "81cdbbf9e097e62fb25ffd9b2e08b79c4616b199d49f958372adb5f473c39542",
    "rootEngine": "/tmp/mls-keyboard-engine.KPSkna/run.log",
    "dmgCandidate": {
      "version": "1.4.5",
      "sha256": "58e067a3d42eed8ba5db44c29202f8becf6d7f249b7fac6cc945f6609c9641b7",
      "verified": "mounted version/deepstrict/helper/symlink/binarymatches PASS"
    },
    "durableAudit": "audit/live-insertion",
    "candidateCodeCommit": "2163e0a3e7fa7f388ba551ef97b69d9a6f0a3126",
    "publication": "1.4.5 pushed/rawVERSION/publicarchiveSHA/embeddedcommit/all55SourcesTools verified",
    "installedBackup": "/var/folders/s7/blf5jdcs7q7bfjjxbt621w500000gn/T/mls-g22-candidate.zaw8onaw/installed-1.4.4-backup.app",
    "installedVersion": "1.4.5",
    "installedBinarySHA256": "c0d8f234e223623cda80149e3c43eec6a8b520798e09a63c2ffb06633b81dfe9",
    "installedPID": 49664,
    "physicalSpace": "Sourceсрфе caret4 → selected0/4 → nativeUnicode datachatspace → finalchatspace caret5 in bothownedCodexfields; user confirmed chat",
    "permissions": "User repliedready after panels/restart; actual candidate auto insertion works. No root grantTCC.",
    "physicalScope": "Owned CodexIAB contenteditable+textarea physicalSpaceGREEN; mainprivatecomposer/allapps/manualEnterShift notdeclaredpassed"
  },
  "dictationCompletionAudit": {
    "ticket": "26",
    "evidence": "User screenshot fullrecognizedphrase + visibleprefix actualCodexcomposer; unconfirmed recovery",
    "cause": "Concrete production RED: one ACK per notification cancels after duplicate own selection after first16UTF16; actualCodex callback pattern unproven. Independent stale value/caret RED also covered.",
    "privacy": "No publishedscreenshot/privatecomposerautomation/microphone activation",
    "qa": "dictation-completion-qa.md",
    "baseline": "audit/dictation-completion/root-baseline-red.log",
    "candidate": "1.4.6 published/verified; actualCodexspeech manualhandoff pending",
    "initialFrozenSourceSHA": "506f8f646524805c7c09927a2354e1e7485ed09b4cc98b10d516ffe7c009e88a",
    "sourceSHA256": "cf3d4d6e29672b1c9601e0cd4234c9253ee94d3214d45f428a65f9429d351c41",
    "nativeCompletionGroups": 15,
    "manualSpeech": "Requested user update via menu then samephrase in Codex; awaiting response",
    "linux95Reuse": "27identicalCore/Tests/Package hashes",
    "durableAudit": "audit/dictation-completion",
    "codeCommit": "f96f920104b538201d12c51bf7d8d8018eaf5b71",
    "publication": "GitHub VERSION1.4.6 / HTTPSarchiveSHA / PAXcommit / all64approved files exact"
  },
  "previousRelease": {
    "version": "1.4.11",
    "artifact": "MacLayoutSwitcher-1.4.11.dmg",
    "sha256": "220b985a585e112ecd4ac2a42ddba321db3978f33c557f626f236926ddbb57f7",
    "bytes": 11000556,
    "binarySHA256": "5c0b54728f2c043a80e2387838beab291db290276a6ea331097b0c0de14f92d5",
    "helperSHA256": "7e753560e52177d92e33777cebfa2ad3e94e08d8cdd600747d7ddb4c3e7269fe",
    "publication": "verified; metadata-only sync follows; final receipt in outputs",
    "physicalAcceptance": "passed: Bitrix24 зщкефд+Option → portal confirmed by user",
    "installedPID": 85982,
    "installedBackup": "outputs/MacLayoutSwitcher-1.4.10-before-G28-backup.zip",
    "codeCommit": "77e96bec6ce1a54f4d8c624b202fa0bfeb670621",
    "publicCodeArchiveSHA256": "a88a2696e563ffbfb88fa1af383da8509f508479ae241705aeeb6be07f56ce40",
    "verifiedAt": "2026-10-26T07:11:29.249046+00:00",
    "frozenProductFilesVerified": 87,
    "allTrackedFilesVerified": 355
  },
  "safariReplacementAudit": {
    "ticket": "27",
    "installedVersion": "1.4.6",
    "actual": "Uservideo Safari source remains/recovery; exact failedstage unknown",
    "manualAcceptance": "pending",
    "dictionary": "cancelled expansion remains out of scope"
  },
  "reliabilityAudit": {
    "requirement": "G26",
    "tickets": [
      "29",
      "30",
      "31"
    ],
    "actualInstalledFailure": "1.4.8 ghbdtn auto no-op and Option unavailableField; cause unknown",
    "baselineCommit": "01ec68262fb1f4c663a9ae6560410223a116cb00",
    "scope": "shared raw AX focus, physical input integrity, updater/resume/recorder lifecycle; speech/model audited",
    "T29": "rawAX baseline24fails→final50pass; installed1.4.9, actualcause/acceptance unknown",
    "T30": "fullfinalEngine27groups incl160navigation and interruptionGREEN",
    "T31": "updater15/actualhiddenNSWindow/resume/rawstart/dictation15/fullEngineGREEN",
    "reviews": "two independent finalapproved0findings, exact99hashes",
    "manualAcceptance": "FAILED 1.4.9: user screenshot AXFrontmost=ok; SystemFocus=-25212; AppFocus=-25212",
    "evidence": "audit/reliability",
    "release": "1.4.9 exactsigned installed singlePID14682; code45d6221 pushed/archive verified99files; physicalpending"
  },
  "noValueFocusAudit": {
    "actual": "1.4.9 physicalFAILED",
    "diagnostic": "AXFrontmost=ok;SystemFocus=-25212;AppFocus=-25212",
    "meaning": "SDK noValue; not permission denial or timeout",
    "ticket": "32",
    "qa": "no-value-focus-qa.md",
    "sourceEvidence": "Installed Codex Framework Chromium 155.0.8059.80; exact primary source enhanced accessibility debounced 2s, no manual hook",
    "contract": "Bounded once-per-process preparation; no initial field means fresh operation required after readiness, no stale delayed mutation",
    "candidate": "1.4.10 installed/published; physical Option and Space in Codex confirmed by user",
    "native": "Final raw77; adapters; root Engine/navigation + completion; fullspeech/mountedDMG",
    "reviews": "Both independent final approved; process-replacement race fixed",
    "linux": "95 tests reused by exact27input hashes",
    "durableEvidence": "audit/no-value-focus",
    "codeCommit": "72c48b6af12d85e0da244fc55285e00d3fe446f7",
    "publication": "raw GitHub VERSION + public HTTPS SHA/PAX + 87 frozen/332 tracked file hashes verified",
    "confirmedAt": "2026-10-25T12:24:37.905378+00:00"
  },
  "browserFamilyAudit": {
    "ticket": "33",
    "actual": "Native Bitrix24.app address field noValue; manual:-25205",
    "knownDefect": "Bitrix24 and Yandex frameworks omitted; static BrowserCrApplication/upstream enhanced evidence",
    "browserConfirmation": "User explicitly answered Приложение Битрикс24",
    "priorCodexAcceptance": "1.4.10 Option and Space confirmed 25.10",
    "candidate": "1.4.11 installed/published; actual Bitrix24 Option accepted",
    "scope": "Two exact framework names only; Bitrix target plus confirmed relatedYandex omission",
    "validation": "RED24/GREEN147; two independent approvals; fullspeech/DMG; exactLinux95 reuse",
    "physicalAcceptance": "passed: user answered Да, получилось portal",
    "durableEvidence": "audit/browser-family",
    "codeCommit": "77e96bec6ce1a54f4d8c624b202fa0bfeb670621",
    "publication": "public HTTPS/rawVERSION/PAX/all355 Git blobs verified",
    "confirmedAt": "2026-10-26T09:36:58.857391+00:00"
  },
  "previousManualAcceptance": {
    "version": "1.4.10",
    "status": "passed",
    "confirmedAt": "2026-10-25T12:24:37.905378+00:00",
    "note": "User replied «Да, сейчас работает» to ghbdtn+Option and separate ghbdtn+Space verification in Codex. Scope is these physical paths; no new claim for dictation, Enter, or every app."
  },
  "spotlightFocusAudit": {
    "ticket": "34",
    "diagnostic": "AXFrontmost=ok; SystemFocus=foreign-owner; AppFocus=not-read",
    "userConfirmation": "Да, Spotlight",
    "status": "complete: installed/published and actual Spotlight Option accepted",
    "baseline": "6241c86d769382413cbb6e63f59816ada55e2ee5",
    "physicalAcceptance": "passed: Да, получилось «привет»",
    "v1Manifest": "e189e575698aeef6ef91f24d980e5a5921f6c9528088f3e663a3103f598af16b",
    "review": "both final approved0 after2P1repairs",
    "nativeMetadata": "Cocoa launchDate nil; kernel136byte start verified",
    "integration": "root fullEngine27groups PASS with bounded readiness and immutable realTISfixture",
    "scratch": "/tmp/mls-g29-release.xzt21cmz",
    "candidate": "1.4.12",
    "finalManifestSHA256": "6170dbc8f72a6754a851a8fa0954be8d1c392ab8ee2f6acffd0250081df0a164",
    "evidence": "audit/spotlight-focus",
    "installedPID": 46563,
    "codeCommit": "dba351ccdd82cd737661531e744dc0bd2c5b33e7",
    "publication": "rawVERSION/publicHTTPS/PAX/all384files verified",
    "confirmedAt": "2026-10-27T03:23:04.365606+00:00"
  },
  "bitrixManualAcceptance": {
    "version": "1.4.11",
    "status": "passed",
    "scope": "Bitrix24 native app зщкефд+Option → portal",
    "note": "User answered «Да, получилось portal» after actual Bitrix24 зщкефд+Option without selection. This confirms manual conversion in that field; Yandex, auto separators and dictation were not part of this test.",
    "confirmedAt": "2026-10-26T09:36:58.857391+00:00"
  },
  "fork": {
    "repository": "alimp01/mac-layout-switcher-next",
    "base": "7043925e2f4f7028c6cb1539669290dbf5e0d446",
    "upstream": "iffuno/keyboop@fb9bdde4eb8f13a486974cf102a8bec9d607e5d2",
    "status": "released; scoped physical acceptance passed",
    "version": "1.5.0",
    "manualAcceptance": "Codex: physical ghbdtn + Space and separate ghbdtn + Option without selection",
    "repositoryCreated": true,
    "baselineBranch": "upstream-base",
    "validation": {
      "nilAXSpace": "native GREEN",
      "nilAXOption": "native GREEN",
      "rapidInput": "native GREEN",
      "live": "native GREEN including manual/snippet/caret repairs",
      "detectorAssertions": 4325,
      "manualAcceptance": "Codex: physical ghbdtn + Space and separate ghbdtn + Option without selection",
      "linuxDetectorTests": {
        "passed": 103,
        "failed": 0,
        "commit": "3735b80aa9e4c213bdeeea6b14c6b6900382d762",
        "logSHA256": "007cad9f23430f244ff53b8d1f7d5711271644bd61610dae5f7710eed78c2ecf"
      },
      "dictation": "root adapter + completion + panel PASS",
      "speechBuild": "final v3 full native arm64 PASS",
      "nativeCore": {
        "methods": 110,
        "assertions": 4593,
        "failed": 0,
        "kind": "native supplemental assertion adapter; final Linux pending"
      },
      "linuxFinal": {
        "passed": 110,
        "failed": 0,
        "commit": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f"
      },
      "dmg": "mounted/deepstrict/allfiles/helper/resources PASS"
    },
    "reviewedCommits": {
      "T35": "31d71a7",
      "T36": "3735b80aa9e4c213bdeeea6b14c6b6900382d762",
      "T37": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f"
    },
    "reviewRepairs": [
      "preserve manual Option choice during live correction",
      "reserve snippet triggers and prefixes during quiet-time decisions",
      "preserve caret-edit guard through app/AX context resets",
      "keep known protected fields blocked while AX unavailable; scope by application PID"
    ],
    "codeCommit": "a0b060076612c5fe0c4cb98056a9f10e775a8d2f",
    "finalManifestSHA256": "77fc86007fefe2b1a6962f3a76639bfc023cb611f73bc362f15080cb54fa550b",
    "review": "Spec APPROVE0 / Standards APPROVE0"
  },
  "upstreamRelease": {
    "version": "1.4.12",
    "binarySHA256": "032e5f19503a9bb611eb1c1f6be7d1813539bb94d1a054d673c7d00e280324bc",
    "helperSHA256": "e955d4e78e10a42388f77a3c988f05b1f3dbc8cbb02164283fc9d10a62bc7f39",
    "sha256": "73b8d583ce650c5ce47eb5e870bcd6e4816dc44e7369c25ce8783972ff1a7284",
    "bytes": 10997407,
    "artifact": "MacLayoutSwitcher-1.4.12.dmg",
    "mountedVerified": true,
    "deepStrictVerified": true,
    "publication": "raw VERSION/public HTTPS archive/PAX/all384 files verified; metadata-only sync follows; final receipt in outputs",
    "physicalAcceptance": "passed: user confirmed Spotlight ghbdtn+Option → привет without selection on2026-10-27",
    "installedPID": 46563,
    "installedBackup": "/Users/ilyaalimpiev/Documents/Codex/2026-09-16/mac-layout-switcher-punto-caramba-switcher/outputs/MacLayoutSwitcher-1.4.11-before-G29-backup.zip",
    "frozenManifestSHA256": "6170dbc8f72a6754a851a8fa0954be8d1c392ab8ee2f6acffd0250081df0a164",
    "codeCommit": "dba351ccdd82cd737661531e744dc0bd2c5b33e7",
    "publicCodeArchiveSHA256": "b1f2e4ea6fb08cc901608bec34d1ee2a887bb642357a496225ab4a58b1206fc7",
    "allTrackedFilesVerified": 384,
    "verifiedAt": "2026-10-26T16:43:25.254023+00:00"
  },
  "upstreamManualAcceptance": {
    "version": "1.4.12",
    "status": "passed",
    "scope": "Spotlight ghbdtn+Option without selection",
    "askedAt": "2026-10-26T16:42:26.566268+00:00",
    "answer": "Да, получилось «привет»",
    "confirmedAt": "2026-10-27T03:23:04.365606+00:00",
    "confirmedDateMoscow": "2026-10-27",
    "result": "ghbdtn + Option without selection → привет in actual Spotlight"
  },
  "upstreamTests": {
    "passed": 95,
    "failed": 0,
    "note": "G26 exact27 Linuxinputs95/95; rawfocus50/nav160/update15/dictation15/finalEngine27groups/fullspeech/deepstrict/mountedDMG PASS; two fresh reviews99hashes0findings. Physicalacceptance pending."
  }
};
