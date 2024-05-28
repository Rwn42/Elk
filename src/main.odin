package main

import "core:fmt"
import "core:mem/virtual"
import "core:os"

import "frontend"


main :: proc() {
    string_arena: virtual.Arena
    ast_arena: virtual.Arena
    _ = virtual.arena_init_growing(&string_arena)
    _ = virtual.arena_init_growing(&ast_arena)
    defer free_all(virtual.arena_allocator(&string_arena))
    defer free_all(virtual.arena_allocator(&ast_arena))

    sm := frontend.String_Manager{
        arena = &string_arena,
        allocations = make([dynamic]string, virtual.arena_allocator(&string_arena)),
    }

    filename := "./test/test.elk"

    data, ok := os.read_entire_file(filename)
    if !ok {
        fmt.printf("Error: Unable to open file %s\n", filename)
        return
    }
    defer delete(data)
    

    lexer := frontend.lexer_new(&sm, data, filename)
    parser, parser_ok := frontend.parser_new(&lexer, virtual.arena_allocator(&ast_arena))

    stmt, stmt_ok := frontend.parse_statement(&parser)
    if stmt_ok != true do panic("oh no!")
    fmt.printfln("%#v", stmt)



}


