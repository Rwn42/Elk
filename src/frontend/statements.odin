package frontend

import "core:fmt"

Elk_Statement :: union {
    ^Elk_Variable_Declaration,
    ^Elk_Function_Declaration,
    Elk_Return,
    Elk_Expression,
}

Elk_Return :: distinct Elk_Expression

Elk_Variable_Declaration :: struct {
    name: Token,
    type: Maybe(Token),
    value: Maybe(Token),
}

Elk_Function_Declaration :: struct {
    name: Token,
    return_type: Maybe(Elk_Type),
    params: []Identifer_Type_Pair,
    body: []Elk_Statement,
}

Elk_Type :: union {
    ^Elk_Pointer_Type,
    Elk_Basic_Type,
}

Elk_Basic_Type :: distinct Token

Elk_Pointer_Type :: struct {
    pointing_to: Elk_Type
}

Identifer_Type_Pair :: struct {
    name: Token,
    type: Elk_Type,
}

parse_statement :: proc(using parser: ^Parser) -> (stmt: Elk_Statement, ok: bool) {
    #partial switch token.kind {
        case .Identifier:
            if peek.kind != .Colon do return parse_expression(parser)
            parser_assert(parser, token.kind, .Colon) or_return
            #partial switch token.kind {
                case .Equal: //type infered var decl
                case .Identifier: //type given variable declaration
                case .Fn: return parse_function(parser)
                case .Struct: //struct decl
                case:
                    elk_error("Unexpected Token %s", token.location, token.kind)
                    return {}, false
            }
        case .If: unimplemented("if statements not implemented")
        case .For: unimplemented("for loops not implemented")
        case .While: unimplemented("while not implemented")
        case .Return:
            parser_advance(parser)
            expr, ok := parse_expression(parser)
            return cast(Elk_Return)expr, ok
        case: 
            elk_error("Statement cannot start with %v", token.location, token.kind)
            return nil, false
    }

    return nil, true
}

parse_type :: proc(using parser: ^Parser) -> (typ: Elk_Type, ok: bool) {
    tk := token
    parser_advance(parser) or_return
    #partial switch tk.kind {
        case .Identifier: return cast(Elk_Basic_Type)tk, true
        case: unimplemented("type parser not implemented")
    }
}

parse_id_type_pair :: proc(using parser: ^Parser) -> (pairs: []Identifer_Type_Pair, ok: bool) {
    pairs_builder := make([dynamic]Identifer_Type_Pair, node_allocator)

    for {
        ident := parser_assert_return(parser, .Identifier) or_return
        parser_assert(parser, .Colon) or_return
        typ := parse_type(parser) or_return
        append(&pairs_builder, Identifer_Type_Pair{name = ident, type = typ})
        if token.kind != .Comma do break
        parser_advance(parser) or_return
    }

    return pairs_builder[:], true
}

parse_function :: proc(using parser: ^Parser) -> (stmt: Elk_Statement, ok: bool) {
    func_decl := new(Elk_Function_Declaration, parser.node_allocator)

    parser_assert(parser, token.kind, .Lparen) or_return

    func_decl.params = parse_id_type_pair(parser) or_return

    parser_assert(parser, .Rparen) or_return
    func_decl.return_type = token.kind == .Equal ? nil : parse_type(parser) or_return
    parser_assert(parser, .Equal, .Lbrace) or_return

    body_builder := make([dynamic]Elk_Statement, node_allocator) //great name

    for token.kind != .Rbrace{
        append(&body_builder, parse_statement(parser) or_return)
    }

    func_decl.body = body_builder[:]

    return func_decl, true
}