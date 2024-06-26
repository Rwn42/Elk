package frontend

import "core:fmt"

Elk_Statement :: union {
    ^Elk_Variable_Declaration,
    ^Elk_Function_Declaration,
    ^Elk_Struct_Declaration,
    ^Elk_Type_Alias,
    ^Elk_Import,
    Elk_Return,
    Elk_Expression,
}

Elk_Return :: distinct Elk_Expression

Elk_Variable_Declaration :: struct {
    name: Token,
    type: Maybe(Elk_Type_Node),
    value: Maybe(Elk_Expression),
}

Elk_Function_Declaration :: struct {
    name: Token,
    return_type: Maybe(Elk_Type_Node),
    params: []Identifer_Type_Pair,
    body: []Elk_Statement,
}

Elk_Type_Alias :: struct {
    name: Token,
    type: Elk_Type_Node,
}

Elk_Struct_Declaration :: struct {
    name: Token,
    fields: []Identifer_Type_Pair,
}

Elk_Import :: struct {
    path: Token,
    alias: Token,
}

Elk_Type_Node :: union {
    ^Elk_Pointer_Type,
    Elk_Basic_Type,
    ^Elk_Array_type,
    ^Elk_Slice_Type,
}

Elk_Basic_Type :: distinct Token

Elk_Pointer_Type :: struct {
    pointing_to: Elk_Type_Node
}

Elk_Slice_Type :: struct {
    backing_type: Elk_Type_Node,
}

Elk_Array_type :: struct {
    length_token: Token,
    backing_type: Elk_Type_Node,
}

Identifer_Type_Pair :: struct {
    name: Token,
    type: Elk_Type_Node,
}

parse_statement :: proc(using parser: ^Parser) -> (stmt: Elk_Statement, ok: bool) {
    initial := token
    #partial switch token.kind {
        case .Identifier:
            if peek.kind != .Colon do return parse_expression(parser)
            parser_assert(parser, token.kind, .Colon) or_return
            #partial switch token.kind {
                case .Equal: return parse_var_decl(parser, initial, nil)
                case .Fn: return parse_function(parser, initial)
                case .Import: return parse_import(parser, initial)
                case .Struct: return parse_struct_decl(parser, initial)
                case .Alias: return parse_type_alias(parser, initial)
                case: return parse_var_decl(parser, initial, parse_type(parser) or_return)
            }
        case .If: unimplemented("if statements not implemented")
        case .For: unimplemented("for loops not implemented")
        case .While: unimplemented("while not implemented")
        case .Return:
            parser_advance(parser)
            expr, ok := parse_expression(parser)
            return cast(Elk_Return)expr, ok
        case: return parse_expression(parser)
    }

    return nil, true
}

parse_type :: proc(using parser: ^Parser) -> (typ: Elk_Type_Node, ok: bool) {
    tk := token
    parser_advance(parser) or_return
    #partial switch tk.kind {
        case .Identifier: return cast(Elk_Basic_Type)tk, true
        case .Hat:
            pointer_type := new(Elk_Pointer_Type, node_allocator)
            pointer_type.pointing_to = parse_type(parser) or_return
            return pointer_type, true
        case .Lbracket:
            //slice
            if token.kind == .Rbracket {
                parser_advance(parser) or_return
                slice_type := new(Elk_Slice_Type, node_allocator)
                slice_type.backing_type = parse_type(parser) or_return
                return slice_type, true
            }
            //fixed array
            array_type := new(Elk_Array_type, node_allocator)
            if token.kind != .Number {
                panic("arrays with out number literal length unimplemented")
            }
            array_type.length_token = token
            parser_assert(parser, token.kind, .Rbracket)
            array_type.backing_type = parse_type(parser) or_return
            return array_type, true
        case:
            elk_error("Unexpected token %s expected a type", token.location, token.kind)
            return nil, false
    }
}

parse_id_type_pair :: proc(using parser: ^Parser, end: TokenType) -> (pairs: []Identifer_Type_Pair, ok: bool) {
    pairs_builder := make([dynamic]Identifer_Type_Pair, node_allocator)

    for {
        ident := token
        parser_assert(parser, .Identifier, .Colon) or_return
        typ := parse_type(parser) or_return
        append(&pairs_builder, Identifer_Type_Pair{name = ident, type = typ})
        if token.kind != .Comma do break
        parser_advance(parser) or_return
        if token.kind == end do break
    }

    return pairs_builder[:], true
}

parse_var_decl :: proc(using parser: ^Parser, name: Token, type: Maybe(Elk_Type_Node)) -> (stmt: Elk_Statement, ok: bool) {
    var_decl := new(Elk_Variable_Declaration, parser.node_allocator)
    var_decl.name = name
    var_decl.type = type

    if token.kind != .Equal do return var_decl, true

    parser_advance(parser) or_return

    var_decl.value = parse_expression(parser) or_return

    return var_decl, true
}

parse_type_alias :: proc(using parser: ^Parser, name: Token) -> (stmt: Elk_Statement, ok: bool) {
    alias := new(Elk_Type_Alias, parser.node_allocator)
    parser_assert(parser, token.kind, .Equal) or_return
    alias.name = name
    alias.type = parse_type(parser) or_return
    return alias, true
}

parse_struct_decl :: proc(using parser: ^Parser, name: Token) -> (stmt: Elk_Statement, ok: bool) {
    struct_decl := new(Elk_Struct_Declaration, parser.node_allocator)
    struct_decl.name = name

    parser_assert(parser, token.kind, .Equal, .Lbrace) or_return

    struct_decl.fields = parse_id_type_pair(parser, .Rbrace) or_return

    parser_assert(parser, .Rbrace)

    return struct_decl, true
}

parse_import :: proc(using parser: ^Parser, name: Token) -> (stmt: Elk_Statement, ok: bool) {
    import_stmt := new(Elk_Import, parser.node_allocator)
    import_stmt.alias = name

    parser_assert(parser, token.kind, .Equal) or_return
    import_stmt.path = token
    parser_assert(parser, .String)

    return import_stmt, true
}

parse_function :: proc(using parser: ^Parser, name: Token) -> (stmt: Elk_Statement, ok: bool) {
    func_decl := new(Elk_Function_Declaration, parser.node_allocator)
    func_decl.name = name

    parser_assert(parser, token.kind, .Lparen) or_return

    if token.kind != .Rparen do func_decl.params = parse_id_type_pair(parser, .Rparen) or_return

    parser_assert(parser, .Rparen) or_return
    func_decl.return_type = token.kind == .Equal ? nil : parse_type(parser) or_return
    parser_assert(parser, .Equal, .Lbrace) or_return

    body_builder := make([dynamic]Elk_Statement, node_allocator) //great name

    for token.kind != .Rbrace{
        //TODO: try and parse another statement so multiple errors can be caught
        append(&body_builder, parse_statement(parser) or_return) 
    }

    parser_advance(parser) or_return

    func_decl.body = body_builder[:]

    return func_decl, true
}

symbol_name :: proc(stmt: Elk_Statement) -> string {
    #partial switch value in stmt {
        case ^Elk_Function_Declaration: return value.name.data.(string)
        case ^Elk_Struct_Declaration: return value.name.data.(string)
        case ^Elk_Type_Alias: return value.name.data.(string)
        case ^Elk_Variable_Declaration: return value.name.data.(string)
        case: panic("Cannot get symbol name for statement type")
    }
}