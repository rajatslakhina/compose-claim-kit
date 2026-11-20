import Testing
@testable import ComposeClaimKit

@Suite("Reading addresses, mappings and substitutions")
struct ReaderTests {
    let stackScene = sceneOf(webAndDB)

    func addresses(_ sentence: String, _ scene: Scene? = nil) -> [ComposeClaim.Address] {
        AddressReader.claims(sentence, scene: scene ?? stackScene).compactMap { claim in
            if case let .address(address) = claim.subject { return address }
            return nil
        }
    }

    @Test func addressTokens() {
        let project = stackScene.project
        #expect(AddressReader.parse("http://localhost:8080/path")?.port == 8080)
        #expect(AddressReader.parse("postgres://u:p@db:5432/app")?.host == "db")
        #expect(AddressReader.parse("URL=redis://cache:6379.")?.host == "cache")
        #expect(AddressReader.parse("[::1]:80")?.host == "[::1]")
        #expect(AddressReader.parse("8080:80") == nil)
        #expect(AddressReader.parse("db") == nil)
        #expect(AddressReader.parse("db:x") == nil)
        #expect(AddressReader.parse(":80") == nil)
        #expect(AddressReader.parse("a+b:80") == nil)
        #expect(AddressReader.parse("db:99999") == nil)
        #expect(AddressReader.addresses(in: "use `postgres:16` or image postgres:16", project: project).isEmpty)
        #expect(AddressReader.addresses(in: "nginx:1.27 db:5432 db:5432 other:1", project: project).count == 1)
    }

    @Test func vantage() {
        #expect(addresses("Open `http://localhost:8080` in your browser.").map(\.vantage) == [.host])
        #expect(addresses("The `app` container connects to `localhost:5432`.").map(\.vantage) == [.service("app")])
        #expect(addresses("It is listening on `localhost:8080`, the container port 80.").map(\.vantage) == [.host])
        #expect(addresses("The value is `localhost:8080`.").isEmpty)
        #expect(addresses("`app` and `web` connect to `localhost:8080`.").isEmpty)
        #expect(addresses("`app` connects to `db:5432`.").map(\.vantage) == [.service("app")])
        #expect(addresses("Containers connect to `db:5432`.").map(\.vantage) == [.service(nil)])
        #expect(addresses("Open `db:5432` in your browser.").isEmpty)
        #expect(addresses("Don't use `localhost:5432` from `app`.").isEmpty)
        #expect(AddressReader.claims("Open `localhost:8080`.", scene: Scene()).isEmpty)
        let broken = Scene(reading: .unreadable("why"))
        #expect(addresses("Open `localhost:8080` in your browser.", broken).map(\.vantage) == [.host])
        #expect(AddressReader.addresses(in: "localhost:80 db:1", project: nil).map(\.host) == ["localhost"])
        #expect(AddressReader.lines(Scene()).isEmpty)
    }

    @Test func mappings() {
        func mapping(_ sentence: String) -> ComposeClaim.Subject? {
            MappingReader.claims(sentence, scene: stackScene).first?.subject
        }
        #expect(mapping("`8080:80` maps host port 8080 to container port 80.") == .mapping(published: 8080, target: 80))
        #expect(mapping("It maps port 80 in the container to port 8080 on the host.")
            == .mapping(published: 8080, target: 80))
        #expect(mapping("It maps port 80 inside the container to 8080 on your machine.")
            == .mapping(published: 8080, target: 80))
        #expect(mapping("Host port 8080 is open.") == nil)
        #expect(mapping("It does not map host port 8080 to container port 80.") == nil)
        #expect(MappingReader.claims("host port 1 container port 2", scene: Scene()).isEmpty)
    }

    func resolves(_ sentence: String) -> [ComposeClaim.Resolves] {
        ResolveReader.claims(sentence, scene: Scene()).compactMap { claim in
            if case let .resolves(resolves) = claim.subject { return resolves }
            return nil
        }
    }

    @Test func substitutions() {
        let unset = resolves("With `TAG` unset, `${TAG:-latest}` becomes `latest`.")
        #expect(unset == [.init(expression: "${TAG:-latest}", condition: .unset("TAG"), claimed: .value("latest"))])
        #expect(resolves("If `TAG` is empty, `${TAG-x}` gives an empty string.").first?.claimed == .value(""))
        #expect(resolves("If `TAG` is empty, `${TAG-x}` gives an empty string.").first?.condition == .empty("TAG"))
        #expect(resolves("`${TAG:?set it}` fails when `TAG` is not set.").first?.claimed == .failure)
        #expect(resolves("`${TAG:?set it}` fails when `TAG` is not set.").first?.condition == .unset("TAG"))
        #expect(resolves("With `TAG=1.2`, `${TAG}` is `1.2`.").first?.condition == .set("TAG", "1.2"))
        #expect(resolves("With `TAG=`, `${TAG}` is empty.").first?.condition == .empty("TAG"))
        #expect(resolves("When `TAG` is set to `2`, `${TAG}` gives you `2`.").first?.condition == .set("TAG", "2"))
        #expect(resolves("`${TAG}` gives you `2`.").first?.condition == nil)
        #expect(resolves("`${TAG}` gives a value.").isEmpty)
        #expect(resolves("`${TAG}` is great.").isEmpty)
        #expect(resolves("Use `${TAG}`.").isEmpty)
        #expect(resolves("It is `${TAG}`").isEmpty)
        #expect(resolves("`${TAG}` becomes").isEmpty)
        #expect(ResolveReader.condition([("x", false), ("TAG", true)], skipping: 9) == nil)
        #expect(ResolveReader.spaced("A,  b!") == " a b ")
    }
}
