package frontend

import "base:runtime"

import "core:fmt"

Parser :: struct {
    lexer: ^Lexer,

    token: Token,
    peek: Token,

    node_allocator: runtime.Allocator,
}


parser_new :: proc(lexer: ^Lexer, node_allocator: runtime.Allocator) -> (parser: Parser, ok: bool) {
    token_primary := lexer_next(lexer) or_return
    token_peek := lexer_next(lexer) or_return
    return Parser{ 
        lexer = lexer, 
        token = token_primary, 
        peek = token_peek, 
        node_allocator = node_allocator, 
    }, true
}

parser_advance :: proc(using parser: ^Parser) -> (ok: bool) {
    token = peek
    peek = lexer_next(lexer) or_return
    return true
}

parser_assert :: proc(using parser: ^Parser, expected: ..TokenType) ->  bool{
    for expect in expected{
        if token.kind != expect {
            elk_error("Unexpected token %v expected %v", token.location, token.kind, expected)
            return false
        }
        if parser_advance(parser) == false do return false
    }
    return true
}   

parser_assert_return :: proc(using parser: ^Parser, expected: TokenType) -> (Token, bool) {
    tk := token 

    if tk.kind != expected do return {}, false

    if parser_advance(parser) == false do return {}, false

    return tk, true
}