# TC32-V

**TC32-V** é o nome da microarquitetura: um core RISC-V RV32 escrito do zero em SystemVerilog, como projeto pessoal de aprendizado,
portfólio e possível TCC de uma pós em microeletrônica digital. O autor está no primeiro
contato com HDL: priorize código legível e didático em vez de código esperto.

## Roteiro (para contexto; só a etapa atual está em andamento)

- **Etapa 0 (atual):** módulos pequenos (ALU, banco de registradores, contador, UART TX) e
  o ambiente de verificação.
- **Entrega 1:** RV32I single-cycle (capítulo 7 do Harris & Harris) rodando `riscv-tests` e um
  programa em C.
- **Entrega 2:** pipeline de 5 estágios; co-simulação contra o Spike.
- **Entrega 3:** extensões M e A, Zicsr, Wishbone, riscv-arch-test e riscv-formal.
- **Entrega 4:** modos S/U, MMU Sv32 e Linux.
- **Depois:** um repositório de chip separado, gerado do template GF180MCU da wafer.space
  (LibreLane), instancia este core como submódulo. Não adicione LibreLane, pads nem PDK aqui.

## Ferramentas

Toda a stack vem do **OSS CAD Suite** numa release de data fixa, definida no `tools.lock` e
instalada sem root por `make tools` em `~/.local/opt`. O mesmo caminho vale para o PC do
autor (CachyOS, shell fish), o PC do laboratório (sem root) e o CI. Não instale ferramentas
por pacote do sistema nem por outro caminho. O host só precisa de `g++` e `make`.

- **Verilator 5.052 ou mais novo** é o único simulador do fluxo automatizado. Versões antigas
  não têm covergroups (5.050+) nem UVM 2020-3.2 (5.052).
- **z3** (vem no OSS CAD Suite): o Verilator chama um solver SMT em tempo de execução para
  `randomize()` com constraints.
- **Yosys** com o frontend **sv-elab** (antigo yosys-slang, comando `read_slang`), usado como
  checagem de que o RTL é sintetizável (`synth_ecp5`, alvo LFE5U-25F) e como segundo lint,
  pelas mensagens de erro melhores. Ele vem embutido a partir do Yosys 0.67; em versões
  anteriores, carregue o plugin com `yosys -m slang`. Não use `read_verilog -sv` para o RTL.
- **Não use cocotb nem Python** para testes. Os testbenches são em SystemVerilog.
- O xsim (Vivado) é usado manualmente pelo autor como segunda opinião; não integre ao CI.

## Regras de RTL (`rtl/`)

- Use: `logic`, `always_ff`, `always_comb`, `enum`, `typedef`, `package`.
- Não use:
  - classes (não sintetizáveis);
  - atrasos `#` (a síntese ignora, e a simulação passa a divergir do hardware);
  - `initial` para dar valor a registradores (no ASIC não existe valor de power-up; use `rst`).
    Exceção: inicializar ROM ou BRAM de FPGA com `$readmemh`;
  - `interface`, por enquanto. O sv-elab suporta, mas na Etapa 0 e na Entrega 1 ela só
    complica, e pode atrapalhar o fluxo formal (SymbiYosys). Reavaliar na Entrega 3, com o
    barramento Wishbone.
- Reset síncrono, ativo em nível alto, sinal `rst`; clock `clk`.
- Prefixo `tc32v_` em todos os módulos e packages (`tc32v_alu`, `tc32v_pkg`), para não colidir
  com outros IPs quando o core for integrado no chip. Identificadores SV não aceitam hífen.
- Um módulo por arquivo, nome do arquivo = nome do módulo.
- O RTL nunca conhece pinos de placa. Tops de placa ficam em `fpga/<placa>/`.
- Assertions SVA podem ficar no RTL dentro de `` `ifndef SYNTHESIS ``, ou num módulo
  separado em `sva/` ligado com `bind` (preferível).
- Todo RTL precisa passar em `make lint` (Verilator `-Wall`) e `make synth` sem warnings novos.

## Regras de testbench (`tb/`)

- Um testbench por módulo: `tb/<modulo>_tb.sv`, top module `<modulo>_tb`
  (por exemplo `tb/tc32v_alu_tb.sv`, módulo `tc32v_alu_tb`).
- Checagens com `assert (cond) else $fatal(1, "mensagem com valores esperado/obtido");`.
- Sucesso termina com `$display("PASS");` seguido de `$finish;`. O código de saída do
  simulador é o veredito do CI.
- Classes, `rand`, constraints e covergroups são permitidos aqui (e só aqui).
- Testes aleatórios recebem a seed por `+verilator+seed+N` e imprimem a seed usada.

## Comandos

- `make tools`: instala as ferramentas fixadas no `tools.lock` (só na primeira vez).
- `make tools-prune`: apaga, com confirmação, versões do OSS CAD Suite que não são a do
  `tools.lock`. Nunca rode isso automaticamente.
- `make lint`: lint de todo o RTL (Verilator `-Wall` e elaboração com sv-elab).
- `make test`: roda todos os testbenches.
- `make test-<modulo>`: roda um testbench.
- `make synth`: síntese de verificação com Yosys.
- `make waves-<modulo>`: roda com dump FST para abrir no GTKWave ou Surfer.
- `SEED=N make test`: muda a seed.
