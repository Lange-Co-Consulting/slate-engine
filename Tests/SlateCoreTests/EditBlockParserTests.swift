import Testing
@testable import SlateCore

@Test func parsesOneBlock() {
    let text = """
    src/A.swift
    ```swift
    <<<<<<< SEARCH
    let x = 1
    =======
    let x = 2
    >>>>>>> REPLACE
    ```
    """
    let blocks = EditBlockParser.parse(text)
    #expect(blocks.count == 1)
    #expect(blocks[0].path == "src/A.swift")
    #expect(blocks[0].search == "let x = 1")
    #expect(blocks[0].replace == "let x = 2")
}

@Test func reusesPreviousPathWhenOmitted() {
    let text = """
    src/A.swift
    ```
    <<<<<<< SEARCH
    a
    =======
    b
    >>>>>>> REPLACE
    ```
    ```
    <<<<<<< SEARCH
    c
    =======
    d
    >>>>>>> REPLACE
    ```
    """
    let blocks = EditBlockParser.parse(text)
    #expect(blocks.count == 2)
    #expect(blocks[1].path == "src/A.swift")
}

@Test func emptySearchMeansCreate() {
    let text = """
    new.txt
    ```
    <<<<<<< SEARCH
    =======
    hello
    >>>>>>> REPLACE
    ```
    """
    let blocks = EditBlockParser.parse(text)
    #expect(blocks[0].search == "")
    #expect(blocks[0].replace == "hello")
}
