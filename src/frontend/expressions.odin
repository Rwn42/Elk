package frontend

import "core:fmt"

Elk_Expression :: union {
    Elk_Number,
    Elk_String,
    Elk_Bool,
    Elk_Identifier,
    ^Elk_Infix_Expression,
    ^Elk_Assignment_Expression,
    ^Elk_Unary_Expression,
    ^Elk_Array_Literal,
    ^Elk_Struct_Literal,
}

Elk_Number :: distinct Token
Elk_String :: distinct Token 
Elk_Bool :: distinct Token
Elk_Identifier :: distinct Token

Elk_Infix_Expression :: struct {
    lhs: Elk_Expression,
    rhs: Elk_Expression,
    operator: Token,
}

Elk_Assignment_Expression :: struct {
    lhs: Elk_Expression,
    rhs: Elk_Expression,
}

Elk_Unary_Expression :: struct {
    rhs: Elk_Expression,
    operator: Token,
}

Elk_Array_Literal :: struct {
    entries: []Elk_Expression,
}

Elk_Struct_Literal :: struct {
    type: Token,
    field_names: []Token,
    field_expressions: []Elk_Expression,
}

Operator_Token: TokenTypeSet : {
    .Dash, .DashEqual, .Dot, .DoubleEqual,
    .Equal, .NotEqual, .Plus, .PlusEqual, .Equal,
    .Asterisk, .AsteriskEqual, .SlashForward, .SlashEqual,
    .LessThan, .LessThanEqual, .GreaterThan, .GreaterThanEqual,
}

Operator_Precedence :: enum {
    Lowest,
    Equals,
    LessGreater,
    Sum,
    Product,
    Prefix,
    Highest,
}

operator_precedence :: proc(kind: TokenType) -> Operator_Precedence {
    #partial switch kind {
        case .NotEqual: return .Equals
        case .LessThan: return .LessGreater
        case .GreaterThan: return .LessGreater
        case .DoubleEqual: return .Equals
        case .Equal: return .Equals
        case .LessThanEqual: return .LessGreater
        case .GreaterThanEqual: return .LessGreater
        case .Plus: return .Sum
        case .Dash: return .Sum
        case .Asterisk: return .Product
        case .SlashForward: return .Product
        case .Dot: return .Highest
        case: return .Lowest
    }
}


parse_expression :: proc(using parser: ^Parser) -> (expr: Elk_Expression, ok: bool) {
    expr = parse_primary_expression(parser, .Lowest) or_return
    if !line_end(token, peek) {
        elk_error("Unexpected Token %v, Expected newline or ;",peek.location, peek.kind)
        return expr, false
    }
    if peek.kind == .SemiColon do parser_advance(parser) or_return
    parser_advance(parser) or_return
    return expr, true
}

parse_primary_expression :: proc(using parser: ^Parser, prec: Operator_Precedence) -> (expr: Elk_Expression, ok: bool) {
    #partial switch token.kind {
        case .Number: expr = cast(Elk_Number)token
        case .True,. False: expr = cast(Elk_Bool)token
        case .String: expr = cast(Elk_String)token
        case .Lparen: expr = parse_grouped(parser) or_return
        case .Lbrace: expr = parse_array_literal(parser) or_return
        case .Hat, .ExclamationMark, .Ampersand, .Dash: expr = parse_prefix(parser) or_return
        case .Identifier:
            #partial switch peek.kind {
                case .Lparen: unimplemented("function calls")
                case .Lbrace: expr = parse_struct_literal(parser) or_return
                case: expr = cast(Elk_Identifier)token
            }
        case: {
            elk_error("Expression cannot start with %v", token.location, token.kind)
            return nil, false
        }
    }

    for !line_end(token, peek) && prec < operator_precedence(peek.kind) {
        if peek.kind not_in Operator_Token do return expr, true
        parser_advance(parser) or_return
        expr = parse_infix(parser, expr) or_return
    }

    return expr, true
}


parse_grouped :: proc(using parser: ^Parser) -> (expr: Elk_Expression, ok: bool){
    parser_advance(parser) or_return
    expr = parse_primary_expression(parser, .Lowest) or_return
    if peek.kind != .Rparen {
        elk_error("Unexpected token %v expected )", token.location, token.kind)
        return nil, false
    }
    parser_advance(parser) or_return
    return expr, true
}

parse_infix :: proc(using parser: ^Parser, lhs: Elk_Expression) -> (expr: Elk_Expression, ok: bool) {
    bin_expr := new(Elk_Infix_Expression, node_allocator)
    bin_expr.lhs = lhs 
    bin_expr.operator = token

    prec := operator_precedence(token.kind)
    parser_advance(parser)

    //dot is right associative subtracting 1 from the precedence seems to work for that
    if bin_expr.operator.kind == .Dot {
        bin_expr.rhs = parse_primary_expression(parser, Operator_Precedence(int(prec) - 1)) or_return
    } else {
        bin_expr.rhs = parse_primary_expression(parser, prec) or_return
    }

    if bin_expr.operator.kind == .Equal{
        assign_expr := new(Elk_Assignment_Expression, node_allocator)
        assign_expr.lhs = bin_expr.lhs
        assign_expr.rhs = bin_expr.rhs
        return assign_expr, true
    }

    return bin_expr, true
}

parse_array_literal :: proc(using parser: ^Parser) -> (expr: Elk_Expression, ok: bool) {
    node := new(Elk_Array_Literal, node_allocator)

    builder := make([dynamic]Elk_Expression, node_allocator)

    parser_assert(parser, .Lbrace) or_return

    if token.kind == .Rbrace do return node, true
    for {
        append(&builder, parse_primary_expression(parser, .Lowest) or_return)
        if peek.kind == .Comma {
            parser_advance(parser) or_return
            parser_advance(parser) or_return
        } else if peek.kind == .Rbrace{
            break
        }
    }
    parser_advance(parser) or_return


    node.entries = builder[:]

    return node, true
}

parse_struct_literal :: proc(using parser: ^Parser) -> (expr: Elk_Expression, ok: bool) {
    struct_literal := new(Elk_Struct_Literal)

    name_builder := make([dynamic]Token, node_allocator)
    expr_builder := make([dynamic]Elk_Expression, node_allocator)
    
    name := token

    struct_literal.type = name

    parser_assert(parser, .Identifier, .Lbrace) or_return

    for token.kind != .Rbrace{
        field_name := token
        parser_assert(parser, .Identifier, .Equal) or_return
        field_expression := parse_primary_expression(parser, .Lowest) or_return
        parser_advance(parser) or_return
        if token.kind == .Comma do parser_advance(parser) or_return
        append(&name_builder, field_name)
        append(&expr_builder, field_expression)
    }

    struct_literal.field_expressions = expr_builder[:]
    struct_literal.field_names = name_builder[:]

    return struct_literal, true

}

parse_prefix :: proc(using parser: ^Parser) -> (expr: Elk_Expression, ok: bool) {
    un_expr := new(Elk_Unary_Expression);
    un_expr.operator = token
    parser_advance(parser) or_return
    un_expr.rhs = parse_primary_expression(parser, .Prefix) or_return
    return un_expr, true
}

line_end :: proc(tk: Token, peek: Token) -> bool {
    return peek.location.row > tk.location.row || peek.kind == .EOF || peek.kind == .SemiColon
}

