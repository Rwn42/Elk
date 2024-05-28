package frontend

Location :: struct {
    row: uint,
    col: uint,
    filename: string,
}

TokenTypeSet :: bit_set[TokenType]

TokenType :: enum {
    Identifier,
    Number,
    String,

    Lparen,
    Rparen,
    Lbrace,
    Rbrace,
    Lbracket,
    Rbracket,

    If,
    Else,
    While,
    For,
    Return,
    Fn,
    True,
    False,
    Struct,

    Dot,
    Comma,
    SemiColon,
    Colon,
    Equal,

    DoubleEqual,
    NotEqual,
    LessThanEqual,
    GreaterThanEqual,
    LessThan,
    GreaterThan,
    ExclamationMark,
    Plus,
    Dash,
    Asterisk,
    SlashForward,
    PlusEqual,
    DashEqual,
    AsteriskEqual,
    SlashEqual,

    EOF,
}

TokenData :: Maybe(string)

Token :: struct {
    kind: TokenType,
    data: TokenData,
    location: Location,
}