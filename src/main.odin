package main

import "core:fmt"
import "core:mem/virtual"
import "core:mem"
import "core:os"

import "backend"
import "frontend"


main :: proc() {
    string_arena: virtual.Arena
    _ = virtual.arena_init_growing(&string_arena)
    defer free_all(virtual.arena_allocator(&string_arena))

    sm := frontend.String_Manager{
        arena = &string_arena,
        allocations = make([dynamic]string, virtual.arena_allocator(&string_arena)),
    }

    filename := "./test/test.elk"    

    _ = compile_file(filename, &sm)
}


compile_file :: proc(filepath: string, sm: ^frontend.String_Manager) -> bool {
    //open the file
    data, ok := os.read_entire_file(filepath)
    if !ok {
        fmt.printf("Error: Unable to open file %s\n", filepath)
        return false
    }
    defer delete(data) //TODO could be deleted earlier 

    //prepare frontend
    file_arena: virtual.Arena
    _ = virtual.arena_init_growing(&file_arena)

    defer free_all(virtual.arena_allocator(&file_arena))

    file_allocator := virtual.arena_allocator(&file_arena)

    lexer := frontend.lexer_new(sm, data, filepath)
    parser, parser_ok := frontend.parser_new(&lexer, file_allocator)
    if !parser_ok do return false

    //after this call our parser is populated with the ast for the file
    frontend.parse(&parser) or_return

    //eventually imports here
    scope_manager := backend.Scope_Manager{}
    ir_context := backend.IR_Context{sm = &scope_manager}

    ok = backend.setup_ir_state(&ir_context, parser.file_level_statements[:])

    for stmt in parser.file_level_statements[:] {
        if func, ok := stmt.(^frontend.Elk_Function_Declaration); ok {
            for body_stmt in func.body {
                ok := backend.ctx_generate_stmt(&ir_context, body_stmt)
                if !ok do panic("backend err")
            }
        }
    }

    for inst in ir_context.program{
        fmt.println(inst)
    }

    if !ok do panic("backend err")

    return true
}