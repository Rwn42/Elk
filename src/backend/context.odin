package backend

import "base:runtime"
import "core:fmt"

import fe"../frontend"

elk_error :: proc(fmt_str: string, args: ..any) {
    fmt.eprintf("Error: ")
    fmt.eprintfln(fmt_str, ..args)
}

Symbol :: struct {
    ast_node: fe.Elk_Statement, //all symbols that would be defined are defined in a statement
    resolved: bool,             //if true the data field is populated (non-nil)
    resolving: bool,            //hacky, used to check for recursive data definitions
    data: union {
        Type_Info,
        Func_Info,
        Local_Info,
        Constant_Info
    }
}

Type_Kind :: enum {
    Struct,
    Pointer,
    FuncPointer,
    Array,
    Natural,
    Integer,
    Real,
    Boolean,
    Byte,
    String,
    Untyped_Number,
    Null,
}

Type_Info :: struct {
    kind: Type_Kind,
    size: uint,
    data: union {
        fe.Elk_Type_Node,
        Struct_Info,
        ^Func_Info,
    }
}

Struct_Info :: []Field_Info
Func_Info :: struct {
    params: []Field_Info,
    return_type: Maybe(Type_Info),
}
Field_Info :: struct {name: string, type: Type_Info}

Constant_Info :: distinct fe.Elk_Expression //TODO figure constants out

Local_Info :: struct {
    stack_offset: uint,
    type: Type_Info,
}

Nesting_Limit :: 32
Block :: map[string]Symbol
Symbol_Stack :: struct {
    allocator: runtime.Allocator,
    scopes: [Nesting_Limit]Block,
    sp: uint,
}

scope_open :: proc(using ss: ^Symbol_Stack) {
    if sp >= Nesting_Limit{
        panic("Fatal Compiler Error: Scope Stack Overflow, too many nested blocks")
    }
    scopes[sp] = make(Block, 16, allocator)
    sp += 1
}

scope_find :: proc(using ss: ^Symbol_Stack, symbol_name: string) -> (Symbol, bool) {
    for idx: int = int(sp - 1); idx >= 0; idx -= 1 {
        symbol, ok := ss.scopes[idx][symbol_name]
        if ok do return symbol, true
    }
    elk_error("Undeclared symbol %s", symbol_name)
    return {}, false
}

scope_find_mut :: proc(using ss: ^Symbol_Stack, symbol_name: string) -> (^Symbol, bool) {
    for idx: int = int(sp - 1); idx >= 0; idx -= 1 {
        symbol, ok := ss.scopes[idx][symbol_name]
        if ok do return &ss.scopes[idx][symbol_name], true
    }
    elk_error("Undeclared symbol %s", symbol_name)
    return nil, false
}



scope_close :: proc(using ss: ^Symbol_Stack) {
    if sp == 0 {
        panic("Fatal Compiler Error: Scope Stack Underflow")
    }
    delete(scopes[sp - 1])
    sp -= 1
}

scope_register :: proc(using ss: ^Symbol_Stack, symbol_name: string, symbol: Symbol) -> bool{
    scope := &scopes[sp - 1]
    if symbol_name in scope {
        elk_error("Redefinition of symbol %s", symbol_name)
        return false
    }
    map_insert(scope, symbol_name, symbol)
    return true
}

IR_Context :: struct {
    allocator: runtime.Allocator,
    symbol_stack: Symbol_Stack,
}

context_create_file_ir :: proc(using ctx: ^IR_Context, ast_roots: []fe.Elk_Statement) -> bool {
    scope_open(&symbol_stack)
    defer scope_close(&symbol_stack)

    for root in ast_roots {
        symbol := Symbol {resolved = false, ast_node = root, data = nil, resolving = false}
        scope_register(&symbol_stack, fe.symbol_name(root), symbol) or_return
    }

    for name, &symbol in symbol_stack.scopes[symbol_stack.sp - 1] {
        if symbol.resolved do continue
        context_resolve_declaration(ctx, name) or_return
    }

    fmt.printf("%#v", symbol_stack.scopes[symbol_stack.sp - 1])

    return true
}

WORD_SIZE :: 8
context_get_type_info :: proc(using ctx: ^IR_Context, node: fe.Elk_Type_Node) -> (info: Type_Info, ok: bool) {
    switch value in node {
        case ^fe.Elk_Pointer_Type: 
            return Type_Info{size = WORD_SIZE, kind = .Pointer, data = value.pointing_to}, true
        case fe.Elk_Basic_Type:
            name := value.data.(string)
            switch name {
                case "nat":  return Type_Info{size = WORD_SIZE, kind = .Natural}, true
                case "int":  return Type_Info{size = WORD_SIZE, kind = .Integer}, true
                case "real": return Type_Info{size = WORD_SIZE, kind = .Real}, true
                case "byte": return Type_Info{size = 1, kind = .Byte}, true
                case "bool": return Type_Info{size = 1, kind = .Boolean}, true
                case:
                    symbol := scope_find(&symbol_stack, name) or_return
                    if !symbol.resolved {
                        if symbol.resolving{
                            elk_error("Recursive Data Definition of Symbol %s", name)
                            return {}, false
                        }
                        context_resolve_declaration(ctx, name) or_return
                    }
                    //symbol should will now be resolved
                    symbol = scope_find(&symbol_stack, name) or_return
                    type_info, is_type := symbol.data.(Type_Info)
                    if !is_type{
                        elk_error("Symbol %s is not a type", name)
                        return {}, false
                    }
                    return type_info, true
            }
    }
    unreachable()
}

context_resolve_declaration :: proc(using ctx: ^IR_Context, name: string) -> bool {
    resolve_function :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Function_Declaration, sym: ^Symbol) -> bool {
        param_builder := make([dynamic]Field_Info)
        defer delete(param_builder)

        sym.resolving = true
        defer sym.resolving = false

        for field in node.params {
            field_type := context_get_type_info(ctx, field.type) or_return
            new_info := Field_Info{
                name = field.name.data.(string), 
                type = field_type
            }
            append(&param_builder, new_info)
        }

        func_info := Func_Info{}
        params := make([]Field_Info, len(param_builder), ctx.allocator)
        for param, idx in param_builder{
            params[idx] = param
        }

        func_info.params = params

        if ret_type, ok := node.return_type.?; ok {
            func_info.return_type = context_get_type_info(ctx, ret_type) or_return
        }

        sym.data = func_info
        sym.resolved = true

        return true

    }
    resolve_struct :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Struct_Declaration, sym: ^Symbol) -> bool {
        field_builder := make([dynamic]Field_Info)
        defer delete(field_builder)
        
        sym.resolving = true
        defer sym.resolving = false

        size: uint = 0
        for field in node.fields {
            field_type := context_get_type_info(ctx, field.type) or_return
            size += field_type.size
            new_info := Field_Info{
                name = field.name.data.(string), 
                type = field_type
            }
            append(&field_builder, new_info)
        }

        fields := make([]Field_Info, len(field_builder), ctx.allocator)
        fields = field_builder[:]

        sym.data = Type_Info{
            size = size,
            kind = .Struct,
            data = Struct_Info(fields)
        }
        sym.resolved = true

        return true
    }
    resolve_alias :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Type_Alias, sym: ^Symbol) -> bool {
        unimplemented("alias")
    }
    resolve_constant :: proc(using ctx: ^IR_Context,  node: ^fe.Elk_Variable_Declaration, sym: ^Symbol) -> bool {
        unimplemented("constants")
    }
    resolve_decl :: proc{
        resolve_function,
        resolve_struct,
        resolve_alias,
        resolve_constant,
    }

    declaration, found := scope_find_mut(&ctx.symbol_stack, name) 
    assert(found, "Attempt to resolve a declaration that was not in the scope stack")
    assert(!declaration.resolved, "Attempt to re-resolve a declaration")
    
    #partial switch value in declaration.ast_node{
        case ^fe.Elk_Function_Declaration: resolve_decl(ctx, value, declaration)
        case ^fe.Elk_Struct_Declaration: resolve_decl(ctx, value, declaration)
        case ^fe.Elk_Variable_Declaration: resolve_decl(ctx, value, declaration)
        case ^fe.Elk_Type_Alias: resolve_decl(ctx, value, declaration)
        case: panic("Tried to resolve an unresovable declaration type")
    }
    return true
}