import Foundation
import NaturalLanguage


enum TaskType: String, Codable {
    case work = "Work"
    case health = "Health"
    case home = "Home"
    case leisure = "Leisure"
    case other = "Other"
}

struct ParsedTask: Codable {
    var title: String
    var date: Date?
    var duration: Double
    var location: String
    var taskType: TaskType
}

// Keyword mapping for lightweight classificaiton for each task
// So gym is likely health etc
// Use lemeatized tokens to make matching more versatile so emails would cover emails-> email.
private let taskTypeKeywords: [String: TaskType] = [
    "gym": .health,
    "run": .health,
    "exercise": .health,
    "workout": .health,
    "doctor": .health,
    "meeting": .work,
    "email": .work,
    "report": .work,
    "clean": .home,
    "laundry": .home,
    "cook": .home,
    "watch": .leisure,
    "movie": .leisure,
    "game": .leisure,
    "work": .work,
    "home": .home,
    "office": .work
]

// Class for the voice input that takes in the string of text and orders them into a structured task

final class VoiceRecognizer {

    // set of known locations otherwise its other
    private let preferredLocations: [String]
    // ensures they can be in captial or lowercase
    init(locations: [String] = []) {
        self.preferredLocations = locations.map { $0.lowercased() }
    }

    // Used to call all the other functions to create the final parsed task
    func parse(text raw: String) -> ParsedTask {
        // currently edited text
        var editedText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // This is the untouched original text we dont clean
        let original = editedText

        // Detects the language
        let lang = detectLanguage(for: original) ?? .english

        // Duration func to strip from title and store duration
        let (durHours, afterDuration) = convertDuration(from: editedText)
        editedText = afterDuration
        let durationHours = durHours ?? 0

        // Date/time we also strip from title and store into the text
        let (date, afterDate) = extractFirstDate(from: editedText)
        editedText = afterDate

        // Location mapping, prefers the known locations et in program
        let nerPlace = extractPlace(from: original, language: lang)
        let biasedPlace = preferKnownLocation(in: original) ?? nerPlace
        let locationOut = (biasedPlace?.isEmpty == false) ? biasedPlace!.capitalized : "Unknown"

        // Lemmas used for more robust keyword matching
        let lemmas = lemmaConvert(in: original, language: lang)
        let taskType = classifyTaskType(from: lemmas)

        // Title: whatever remains fallback to original title if empty
        let title = makeTitle(from: editedText, fallback: original)
        
        // Returns hte structed parsed task
        return ParsedTask(
            title: title,
            date: date,
            duration: durationHours,
            location: locationOut,
            taskType: taskType
        )
    }

    // Detects the language used for lemetisation
    // https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer
    private func detectLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    // Lemmatize keywords so sending emails quickly is broken down into send,email,quickly
    // Aided using https://developer.apple.com/documentation/naturallanguage/nltagger
    // and https://developer.apple.com/documentation/naturallanguage/nltagger/2976536-enumeratetags
    // also aided using https://developer.apple.com/documentation/naturallanguage/identifying-people-places-and-organizations
    private func lemmaConvert(in text: String, language: NLLanguage?) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma]) // Tagger that works iwth lemma
        tagger.string = text
        
        if let language {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }
        // Go through each word in the text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
            // Surface form of a form
            let surfaceWord = String(text[range]).lowercased()
            if let lemma = tag?.rawValue { // if lemma exists perform it and append it
                out.append(lemma.lowercased())
            } else {
                out.append(surfaceWord) // Otherwise fallback
            }
            return true // Continue with process
        }
        return out
    }

    // Extracts the first place names fro mthe text using apples built in named entity recognition
    // such as extracing locations like london
    // aided using https://developer.apple.com/documentation/naturallanguage/identifying-people-places-and-organizations
    private func extractPlace(from text: String, language: NLLanguage?) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        if let language {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }

        var place: String?
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .placeName {
                place = String(text[range])
                return false
            }
            return true
        }
        return place
    }

    // Classify the task into the selected task types
    private func classifyTaskType(from lemmas: [String]) -> TaskType {
        // look through each predefined keyword and return its task type if found
        for (keyword, type) in taskTypeKeywords {
            // Use lemmas
            if lemmas.contains(keyword) { return type }
        }
        return .other // if not found return location as other
    }

    // Title cleaners by removing leftover words / connecting words
    private func makeTitle(from stripped: String, fallback: String) -> String {
        // Remove stray connectors left behind and tidy whitespace
        var cleaned = tidy(stripped)
        if cleaned.isEmpty {
            cleaned = tidy(fallback)
        }
        return cleaned.capitalized
    }

    // checks if the text contains ak nown location from the lsit of locations and returns it if so
    private func preferKnownLocation(in text: String) -> String? {
        let lower = text.lowercased()
        for loc in preferredLocations {
            if lower.contains(loc) { return loc }
        }
        return nil
    }
    
    // used to try tidy some inbetween words e.g. remove "takes" and "about" from "takes about half an hour"
    // expanding this can help sort out titles even furhter
    private func tidy(_ s: String) -> String {
        // Added "at" to remove dangling "at"
        var out = s.replacingOccurrences(of: #"\b(takes?|for|about|around|in|at)\b"#,
                                         with: "",
                                         options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+", with: " ",
                                       options: .regularExpression)
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    // Date and duration extractors using apples built in data detector
    // aided using the following document: https://nshipster.com/nsdatadetector/
    
    private func extractFirstDate(from text: String) -> (Date?, String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return (nil, text) // if creation fails text with no parsed date
        }
        // convert to readable string for nsrange
        let ns = text as NSString
        // search for first date match
        let range = NSRange(location: 0, length: ns.length)
        if let match = detector.matches(in: text, options: [], range: range).first,
           let date = match.date {
            // remove the matched date
            let stripped = ns.replacingCharacters(in: match.range, with: "")
            // return the text with removed data
            return (date, tidy(stripped))
        }
        return (nil, text) // otherwise return orginal text
    }

    // Converts spelled-out numbers to a nuemric values such as thirty as 30
    // aided using https://developer.apple.com/documentation/foundation/nsregularexpression
    private func converNumberPhrases(_ phrase: String) -> Double? {
        // trim all white spaces
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // if half return 0.5 if quarter return 0.25
        if p == "half" || p == "a half" { return 0.5 }
        if p == "quarter" || p == "a quarter" { return 0.25 }

        // lookup table for ones
        let ones: [String: Double] = [
            "zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,
            "ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,
            "sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19
        ]
        // lookup table for tens
        let tens: [String: Double] = [
            "twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90
        ]

        // handles value with the range of and such as if htey type two and a half hours
        // more range of acceptable inputs
        if let andRange = p.range(of: " and ") {
            let left = String(p[..<andRange.lowerBound])
            let right = String(p[andRange.upperBound...]).replacingOccurrences(of: "^a\\s+",
                                                                                with: "",
                                                                                options: .regularExpression)
            let leftVal = converNumberPhrases(left) ?? 0
            let rightVal: Double? = {
                if right.hasPrefix("half") { return 0.5 }
                if right.hasPrefix("quarter") { return 0.25 }
                return converNumberPhrases(right)
            }()
            if let rv = rightVal { return leftVal + rv }
        }

        // handle simple numbers and tens
        var total: Double = 0
        for token in p.replacingOccurrences(of: "-", with: " ").split(separator: " ") {
            let t = String(token)
            if let v = ones[t] { total += v; continue }
            if let v = tens[t] { total += v; continue }
            if t == "half" { total += 0.5; continue }
            if t == "quarter" { total += 0.25; continue }
            if Double(t) == nil { return nil } // return nothing if its not an expected number
        }
        return total == 0 ? nil : total // return the result or nothing
    }

    // return hours as strings
    private func convertDuration(from text: String) -> (Double?, String) {
        // Keep a copy as we strip parts out of text
        var cleaned = text
        let nsCleaned = cleaned as NSString
        let entireRange = NSRange(location: 0, length: nsCleaned.length)

        // Identify helper words such as takes half about etc
        let helperWords = #"(?:(?:takes|take|for|about|around|in)\s+)?"#

        // Convert fuzzy phrases into actual numbers
        let fuzzyConvertion: [(pattern: String, hours: Double)] = [
            (helperWords + #"half an hour\b"#, 0.5),
            (helperWords + #"(?:an|a) hour\b"#, 1.0),
            (helperWords + #"(?:a )?couple of hours\b"#, 2.0),
            (helperWords + #"(?:a )?few hours\b"#, 3.0),
            (helperWords + #"a few minutes\b"#, 5.0/60.0),
            (helperWords + #"a minute\b"#, 1.0/60.0)
        ]
        
        // Try each fuzzy pattern if one matches strip it and return the cleaned version
        for (pat, hrs) in fuzzyConvertion {
            // Regular expression found
            if let regularExpression = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
               // the possible matched
               let matchedExpression = regularExpression.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: nsCleaned.length)) {
                cleaned = nsCleaned.replacingCharacters(in: matchedExpression.range, with: "")
                return (hrs, tidy(cleaned))
            }
        }

        // Numeric durations like 2 hours or 30 minutes
        if let regularExpression = try? NSRegularExpression(
            // additioanl helper words
            pattern: helperWords + #"(\d+(?:\.\d+)?)\s*(hours?|hrs?|hour|minutes?|mins?|minute)\b"#,
            options: [.caseInsensitive]
            // finds matched expression and returns the duratio nand tied up text
        ), let matchedExpression = regularExpression.firstMatch(in: cleaned, options: [], range: entireRange) {
            let safeString = cleaned as NSString
            let valueStr = safeString.substring(with: matchedExpression.range(at: 1))
            let unit = safeString.substring(with: matchedExpression.range(at: 2)).lowercased()
            if let v = Double(valueStr) {
                let hours = (unit.hasPrefix("hour") || unit.hasPrefix("hr")) ? v : v/60.0
                cleaned = safeString.replacingCharacters(in: matchedExpression.range, with: "")
                return (hours, tidy(cleaned))
            }
        }

        // Word-number durations, such as "two and a half hours"
        let wordNums =
        #"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|half|quarter)(?:[-\s]+(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen))?"#
        let numPhrase =
        helperWords + #"(?:a\s+)?"#
        + "(" + wordNums + #"(?:\s+and\s+(?:a\s+)??(?:half|quarter))?)"#
        + #"\s*(hours?|hrs?|hour|minutes?|mins?|minute)\b"#

        if let regularExpression = try? NSRegularExpression(pattern: numPhrase, options: [.caseInsensitive]),
           let matchedExpression = regularExpression.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length)) {
            let safeString = cleaned as NSString
            let phrase = safeString.substring(with: matchedExpression.range(at: 1))
            let unit = safeString.substring(with: matchedExpression.range(at: 2)).lowercased()
            if let value = converNumberPhrases(phrase) {
                let hours = (unit.hasPrefix("hour") || unit.hasPrefix("hr")) ? value : value/60.0
                cleaned = safeString.replacingCharacters(in: matchedExpression.range, with: "")
                return (hours, tidy(cleaned))
            }
        }

        return (nil, text)
    }
}

