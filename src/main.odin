package main

import "core:fmt"
import "core:mem/virtual"
import "core:mem"
import "core:os"

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
    ast_arena: virtual.Arena
    _ = virtual.arena_init_growing(&ast_arena)
    defer free_all(virtual.arena_allocator(&ast_arena))

    lexer := frontend.lexer_new(sm, data, filepath)
    parser, parser_ok := frontend.parser_new(&lexer, virtual.arena_allocator(&ast_arena))
    if !parser_ok do return false

    //after this call our parser is populated with the ast for the file
    frontend.parse(&parser) or_return

    //eventually imports here

    //figure out the types in this file so we have nessecary context for building IR
    
    return true
}