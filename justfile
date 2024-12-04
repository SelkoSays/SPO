# interactive sictools
[no-exit-message]
[no-cd]
sici *args:
    java -jar {{justfile_directory()}}/sictools.jar {{args}}

# pass args to sictools
[no-exit-message]
[no-cd]
sic *args:
    java -cp {{justfile_directory()}}/sictools.jar {{args}}

# compile and link mutiple .asm files into a.obj
[no-exit-message]
[no-cd]
sicc *args:
    #!/usr/bin/env bash
    arr=({{args}})
    for file in ${arr[@]}; do
        java -cp {{justfile_directory()}}/sictools.jar sic.Asm $file
    done
    files=$(for file in ${arr[@]}; do echo "${file%.*}.obj"; done)
    java -cp {{justfile_directory()}}/sictools.jar sic.Link -o a.obj $files

# Clean folder based on gitignores
[no-cd]
@clean d='.':
    #!/usr/bin/env bash
    shopt -s globstar \
    && cd {{ d }} \
    && git check-ignore ** | xargs -L1 rm 2> /dev/null || true

[no-exit-message]
[no-cd]
x86 source:
    nasm -f elf {{source}}.s
    ld -m elf_i386 -s {{source}}.o -o {{source}}
    rm {{source}}.o

[no-exit-message]
[no-cd]
c86 source:
    gcc -masm=intel -m32 {{source}}.c -o {{source}}