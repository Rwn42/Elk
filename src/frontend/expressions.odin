package frontend

Elk_Expression :: union {
    Elk_Number,
    Elk_String,
    Elk_Bool,
    Elk_Identifier,
    ^Elk_Binary_Expression,
    ^Elk_Unary_Expression,
}

Elk_Number :: distinct Token
Elk_String :: distinct Token 
Elk_Bool :: distinct Token
Elk_Identifier :: distinct Token

Elk_Binary_Expression :: struct {
    lhs: Elk_Expression,
    rhs: Elk_Expression,
    operator: Token,
}

Elk_Unary_Expression :: struct {
    rhs: Elk_Expression,
    operator: Token,
}


Operator_Token: TokenTypeSet : {
    .Dash, .DashEqual, .Dot, .DoubleEqual,
    .Equal, .NotEqual, .Plus, .PlusEqual,
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
    parser_advance(parser) or_return
    return expr, true
}

parse_primary_expression :: proc(using parser: ^Parser, prec: Operator_Precedence) -> (expr: Elk_Expression, ok: bool) {
    #partial switch token.kind {
        case .Number: expr = cast(Elk_Number)token
        case .True,. False: expr = cast(Elk_Bool)token
        case .String: expr = cast(Elk_String)token
        case .Lparen: expr = parse_grouped(parser) or_return
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
    bin_expr := new(Elk_Binary_Expression, node_allocator)
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

    return bin_expr, true
}

line_end :: proc(tk: Token, peek: Token) -> bool {
    return peek.location.row > tk.location.row || peek.kind == .EOF
}

