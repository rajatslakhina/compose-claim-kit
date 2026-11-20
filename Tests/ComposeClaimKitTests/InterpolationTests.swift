import Testing
@testable import ComposeClaimKit

@Suite("Variable substitution and .env")
struct InterpolationTests {
    func value(_ text: String, _ variables: Variables = Variables(shell: ["V": "val", "E": ""]),
               _ semantics: Interpolation.Semantics = Interpolation.Semantics()) -> String? {
        try? Interpolation.resolve(text, variables, semantics).value
    }

    @Test func operators() throws {
        #expect(value("${V}-$V-${V:-d}-${E:-d}-${U:-d}") == "val-val-val-d-d")
        #expect(value("${E-d}|${U-d}|${V:+a}|${E:+a}|${E+a}|${U+a}") == "|d|a||a|")
        #expect(value("$$V and ${U:-${V}}") == "$V and val")
        #expect(value("${E?x}") == "")
        #expect(value("${V:?x}") == "val")
        #expect(throws: Interpolation.Failure.required(name: "E", message: "need E")) {
            try Interpolation.resolve("${E:?need ${N:-E}}", Variables(shell: ["E": ""]))
        }
        #expect(throws: Interpolation.Failure.required(name: "U", message: "")) {
            try Interpolation.resolve("${U?}", Variables())
        }
        let result = try Interpolation.resolve("${U}${W:-x}", Variables(shell: ["W": "w"]))
        #expect(result.unknown == ["U"])
        #expect(result.value == "w")
    }

    @Test(arguments: ["$", "a$", "${", "${V", "${1}", "${V x}", "${V::x}", "$1", "$-", "${V-x"])
    func malformed(text: String) {
        #expect(throws: Interpolation.Failure.malformed) { try Interpolation.resolve(text, Variables()) }
    }

    @Test func misreadings() {
        let variables = Variables(shell: ["V": "sh", "E": ""], dotEnv: ["V": "file"])
        #expect(value("${E-d}", variables, .init(dashCoversEmpty: true)) == "d")
        #expect(value("${E:-d}", variables, .init(colonDashKeepsEmpty: true)) == "")
        #expect(value("${E?x}", variables, .init(questionCoversEmpty: true)) == nil)
        #expect(value("$$V", variables, .init(dollarDollarExpands: true)) == "sh")
        #expect(value("${V}", variables, .init(dotEnvFirst: true)) == "file")
        #expect(value("${V}", variables) == "sh")
        #expect(Interpolation.hasVariables("a $$ b") == false)
        #expect(Interpolation.hasVariables("${A}"))
    }

    @Test func variables() throws {
        var variables = Variables(shell: ["S": "1"], dotEnv: ["D": "2", "Q": ""], unread: ["Q"], unset: ["S"])
        #expect(variables.knows("S") && variables.knows("D") && !variables.knows("Q") && !variables.knows("X"))
        #expect(variables.value("S", dotEnvFirst: false) == nil)
        variables.unset = []
        #expect(variables.value("S", dotEnvFirst: true) == "1")
        let unread = try Interpolation.resolve("${Q:-fallback}", variables)
        #expect(unread.value == "fallback" && unread.unknown == ["Q"])
    }

    @Test func dotEnvFile() {
        let parsed = EnvFile.parse([
            "# comment", "", "A=plain value # trailing", "B=\"quoted # kept \\\"x\\\"\"", "C='single $X'",
            "export D=exported", "E=x#y", "F= spaced", "G=\"line\\nbreak\"", "H='lit\\n'", "I=$OTHER", "J=\"a$B\"",
            "K='open", "L=\"open", "no equals", "1BAD=x", "M="
        ])
        #expect(parsed.values["A"] == "plain value")
        #expect(parsed.values["B"] == "quoted # kept \"x\"")
        #expect(parsed.values["C"] == "single $X")
        #expect(parsed.values["D"] == "exported")
        #expect(parsed.values["E"] == "x#y")
        #expect(parsed.values["F"] == "spaced")
        #expect(parsed.values["G"] == "line\nbreak")
        #expect(parsed.values["H"] == "lit\\n")
        #expect(parsed.values["M"] == "")
        #expect(parsed.unread == ["I", "J", "K", "L"])
        #expect(parsed.values["1BAD"] == nil)
        #expect(EnvFile.value("'") == nil)
        #expect(Names.isName("_A1") && !Names.isName("") && !Names.isName("A-B"))
    }
}
