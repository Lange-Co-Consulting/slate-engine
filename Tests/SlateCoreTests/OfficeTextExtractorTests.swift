import Foundation
import Testing
@testable import SlateCore

@Suite struct OfficeTextExtractorTests {
    @Test func extractsVisibleNamespacedOfficeText() {
        let xml = Data(#"""
        <w:document xmlns:w="urn:word"><w:body><w:p><w:r><w:t>Hello</w:t></w:r>
        <w:r><w:t>offline world</w:t></w:r></w:p><w:p><w:r><w:t>Second paragraph</w:t></w:r></w:p></w:body></w:document>
        """#.utf8)
        let text = OfficeTextExtractor.visibleText(fromXML: xml)
        #expect(text.contains("Hello"))
        #expect(text.contains("offline world"))
        #expect(text.contains("Second paragraph"))
    }

    @Test func malformedXMLFailsClosed() {
        #expect(OfficeTextExtractor.visibleText(fromXML: Data("<broken>".utf8)).isEmpty)
    }
}
