// Keyboop conversion helpers, adapted to the existing SwitcherCore ANSI map.
// MIT: Keyboop contributors. See THIRD_PARTY.md for mapping differences.
import Foundation

enum Keymap {
    static let enToRu: [String: String] = {
        var pairs: [String: String] = [:]
        for ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ;:'\"[]{},.<>`~" {
            let source = String(ch)
            let target = KeyMap.convert(source, to: .ru)
            if source != target { pairs[source] = target }
        }
        return pairs
    }()
    static let ruToEn = Dictionary(uniqueKeysWithValues: enToRu.map { ($1, $0) })

    static func convert(_ text: String, toCyrillic: Bool) -> String {
        convert(text, toCyrillic: toCyrillic, table: nil)
    }

    static func convert(_ text: String, toCyrillic: Bool, table: [Character: Character]?) -> String {
        // This port has no TIS/global dynamic table. The executor uses the same fixed map.
        if let table { return String(text.map { table[$0] ?? $0 }) }
        return KeyMap.convert(String(text.map(straighten)), to: toCyrillic ? .ru : .en)
    }

    static func straighten(_ ch: Character) -> Character {
        switch ch {
        case "\u{2019}", "\u{2018}", "\u{00B4}", "\u{2032}": return "'"
        case "\u{201C}", "\u{201D}", "\u{201F}": return "\""
        default: return ch
        }
    }

    /// Семантические знаки препинания: одинаковы в обеих раскладках (просто на разных клавишах),
    /// поэтому в конце слова их НЕ конвертируем (иначе "." → "ю", "," → "б").
    static let trailingPunctuation = Set<Character>(".,!?;:…")

    /// Умная конвертация: отделяет концевую пунктуацию (оставляет как есть), конвертит ядро.
    /// `ghbdtn.` → `привет.` (а не `приветю`).
    ///
    /// НО: клавиши `,` `.` `;` в EN-раскладке — это И знаки препинания, И буквы **б ю ж**. Если ПОЛНАЯ
    /// конверсия слова (с этим символом КАК БУКВОЙ) даёт валидное слово — символ был буквой, конвертим
    /// целиком: «yj;»→«нож», «[kt,»→«хлеб» (раньше срезались → «но;», «хле,» — порча). Иначе отделяем
    /// как пунктуацию: «ghbdtn.»→«привет.». Только EN→RU (`toCyrillic`); проверка валидности —
    /// `isValidTarget` (словарь RU, передаёт вызывающий, чтобы Keymap не тянул LayoutData).
    static func smartConvert(_ word: String, toCyrillic: Bool, isValidTarget: ((String) -> Bool)? = nil) -> String {
        smartConvert(word, toCyrillic: toCyrillic, isValidTarget: isValidTarget,
                     table: nil)
    }

    /// Чистое ядро `smartConvert` с таблицей снаружи (`nil` = статическая запаска), для стендов.
    static func smartConvert(_ word: String, toCyrillic: Bool, isValidTarget: ((String) -> Bool)?,
                             table: [Character: Character]?) -> String {
        if toCyrillic, let valid = isValidTarget {
            let full = convert(word, toCyrillic: true, table: table)
            if valid(full.lowercased()) { return full }
        }
        var core = Substring(word)
        var trailing = ""
        while let last = core.last, trailingPunctuation.contains(last) {
            trailing = String(peeledMark(last, toCyrillic: toCyrillic, table: table)) + trailing
            core = core.dropLast()
        }
        guard !core.isEmpty else { return word }
        return convert(String(core), toCyrillic: toCyrillic, table: table) + trailing
    }

    /// Каким оставить срезанный концевой знак (задача 263, отзыв #306, 26.09.2026).
    ///
    /// Набор `trailingPunctuation` исходит из того, что знак одинаков в обеих раскладках и просто
    /// лежит на разных клавишах. Для «Русской — ПК» это неправда: клавиша, которая в английской даёт
    /// «?», в ней печатает «,». Человек набрал «Lf?», имея в виду «Да,», а получал «Да?».
    ///
    /// ⚠️ ЗНАК МЕНЯЕМ, ТОЛЬКО КОГДА ТАБЛИЦА ЧЕЛОВЕКА ПЕРЕВОДИТ ЕГО В ДРУГОЙ ЗНАК ИЗ ТОГО ЖЕ НАБОРА.
    /// Если клавиша даёт букву («.»→«ю», «,»→«б», «;»→«ж») или пары нет вовсе, знак остаётся как
    /// набран, ровно как было: «ghbdtn.» по-прежнему «привет.». У Apple «Русской» в паре с U.S. или
    /// ABC таких пар нет («?» и «!» там на тех же клавишах), так что её пользователи разницы не увидят.
    /// Решает сама живая таблица, отдельной настройки нет.
    ///
    /// ⚠️ С РЕДКИМИ ЛАТИНСКИМИ РАСКЛАДКАМИ ПАРЫ ЕСТЬ И У APPLE «РУССКОЙ» (перебор всех установленных
    /// раскладок на ANSI, ISO и JIS, 26.09.2026). Итальянская, польская, бразильская ABNT2, канадская
    /// CSA и ещё несколько кладут концевой знак на клавишу, которая в русской печатает другой знак.
    /// Там знак тоже переводится по клавише. Это то же правило, а не новое: человек жал клавиши
    /// русской раскладки, и концевой знак не исключение.
    ///
    /// ⚠️ ТОЛЬКО В СТОРОНУ КИРИЛЛИЦЫ. Об этом и был отзыв. Обратное направление («Руддщ,» →
    /// «Hello?» у пользователя «ПК») было бы новым поведением, которого никто не просил, поэтому
    /// там знак остаётся как набран.
    private static func peeledMark(_ p: Character, toCyrillic: Bool, table: [Character: Character]?) -> Character {
        guard toCyrillic else { return p }
        let mapped = convert(String(p), toCyrillic: true, table: table)
        guard mapped.count == 1, let m = mapped.first, m != p, trailingPunctuation.contains(m) else { return p }
        return m
    }

    /// Конверсия для правки НА ЛЕТУ, пока слово не дописано (задача 262, отзыв #312, 26.09.2026).
    /// nil означает «ждём следующую клавишу».
    ///
    /// ⚠️ ЗАЧЕМ ЖДАТЬ. Человек печатает «переключение» в английской раскладке. На седьмой клавише, на
    /// «ю», которая в английской даёт «.», правка на лету решала конвертить: детектор читает точку как
    /// букву и видит «переклю». А `smartConvert` проверял по словарю ПОЛНОЕ слово, не находил
    /// недописанное «переклю» и срезал точку как конец предложения. На экране оставалось «перекл.»,
    /// раскладка переключалась, и слово дописывалось как «перекл.чение». Так же «ю», «б», «ж» в
    /// середине любого слова. Правило про концевой знак писалось для конца слова, а здесь слово ещё
    /// не кончилось.
    ///
    /// Поэтому, если `smartConvert` срезал бы концевой знак, который в таблице человека БУКВА,
    /// мид-словные пути не стреляют. Следующая клавиша делает знак внутренним, и «gthtrk.x» честно
    /// даёт «переключ». Если следом пробел, решает обычный путь на границе слова, как и сегодня.
    /// Цена: на таких словах правка на лету приходит на одну клавишу позже.
    ///
    /// ⚠️ ГРАНИЦУ СЛОВА ЭТО НЕ ТРОГАЕТ. «малую», набранное в английской, на пробеле по-прежнему даёт
    /// «малу.»: формы нет в словаре, и что с этим делать, автор решил пока не менять.
    static func liveConvert(_ word: String, toCyrillic: Bool, isValidTarget: ((String) -> Bool)?) -> String? {
        liveConvert(word, toCyrillic: toCyrillic, isValidTarget: isValidTarget,
                    table: nil)
    }

    /// Чистое ядро `liveConvert` с таблицей снаружи (`nil` = статическая запаска), для стендов.
    static func liveConvert(_ word: String, toCyrillic: Bool, isValidTarget: ((String) -> Bool)?,
                            table: [Character: Character]?) -> String? {
        let smart = smartConvert(word, toCyrillic: toCyrillic, isValidTarget: isValidTarget, table: table)
        guard smart != word else { return smart }               // конвертить нечего, всё как было
        let full = convert(word, toCyrillic: toCyrillic, table: table)
        guard smart != full else { return smart }
        // Обе строки один в один по длине и различаются только в срезанных концевых знаках.
        // Ждём, только если такой знак в таблице человека БУКВА: «&» вместо «.» буквой не станет.
        for (s, f) in zip(smart, full) where s != f && f.isLetter { return nil }
        return smart
    }

    /// Ядро слова без концевой пунктуации — для анализа детектором.
    static func core(of word: String) -> String {
        var s = Substring(word)
        while let last = s.last, trailingPunctuation.contains(last) { s = s.dropLast() }
        return String(s)
    }
}

extension String {
    var hasCyrillic: Bool {
        unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
    }
    var hasLatinLetter: Bool {
        unicodeScalars.contains { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }
}
