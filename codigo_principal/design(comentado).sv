//==============================================================================
// TOP: liga o processador à memória de instruções (imem) e à de dados (dmem)
//==============================================================================
module top(input  logic        clk, reset, 
           output logic [31:0] WriteData, DataAdr, 
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;
  
  // instancia o processador e as memórias
  riscvsingle rvsingle(clk, reset, PC, Instr, MemWrite, DataAdr, 
                       WriteData, ReadData);
  imem imem(PC, Instr);                                // memória de instruções
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData); // memória de dados
endmodule


//==============================================================================
// RISCVSINGLE: processador completo = controlador + caminho de dados
//==============================================================================
module riscvsingle(input  logic        clk, reset,
                   output logic [31:0] PC,
                   input  logic [31:0] Instr,
                   output logic        MemWrite,
                   output logic [31:0] ALUResult, WriteData,
                   input  logic [31:0] ReadData);

  logic       ALUSrc, RegWrite, Jump, Zero;
  // [CORREÇÃO 6] PCSrc agora é declarado explicitamente. Antes era um fio
  // "implícito" (criado automaticamente pelo compilador), o que é má prática
  // e pode esconder erros de digitação.
  logic       PCSrc;
  logic [1:0] ResultSrc, ImmSrc;
  logic [2:0] ALUControl;

  // Unidade de controle: olha opcode (Instr[6:0]), funct3 (Instr[14:12]),
  // bit 5 do funct7 (Instr[30]) e a flag Zero da ALU, e gera os sinais de controle
  controller c(Instr[6:0], Instr[14:12], Instr[30], Zero,
               ResultSrc, MemWrite, PCSrc,
               ALUSrc, RegWrite, Jump,
               ImmSrc, ALUControl);

  // Caminho de dados: executa o que os sinais de controle mandam
  datapath dp(clk, reset, ResultSrc, PCSrc,
              ALUSrc, RegWrite,
              ImmSrc, ALUControl,
              Zero, PC, Instr,
              ALUResult, WriteData, ReadData);
endmodule


//==============================================================================
// CONTROLLER: junta o decodificador principal (maindec) e o da ALU (aludec)
//==============================================================================
module controller(input  logic [6:0] op,
                  input  logic [2:0] funct3,
                  input  logic       funct7b5,
                  input  logic       Zero,
                  output logic [1:0] ResultSrc,
                  output logic       MemWrite,
                  output logic       PCSrc, ALUSrc,
                  output logic       RegWrite, Jump,
                  output logic [1:0] ImmSrc,
                  output logic [2:0] ALUControl);

  logic [1:0] ALUOp;   // dica que o maindec dá ao aludec (00=soma, 01=sub, 10=olhar funct3)
  logic       Branch;  // instrução é um desvio condicional (beq)

  // Decodificador principal: gera quase todos os sinais a partir do opcode
  maindec md(op, ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp);

  // Decodificador da ALU: gera ALUControl a partir de ALUOp, funct3 e funct7[5]
  // op[5] distingue R-type (1) de I-type (0) para diferenciar sub de addi
  aludec  ad(op[5], funct3, funct7b5, ALUOp, ALUControl);

  // [CORREÇÃO 3] O PC deve pegar o endereço-alvo (PCTarget) em DOIS casos:
  //   - beq com condição verdadeira (Branch & Zero)
  //   - jal, que é um salto incondicional (Jump)
  // O original só tinha "Branch & Zero", então o jal nunca saltava.
  assign PCSrc = (Branch & Zero) | Jump;
endmodule


//==============================================================================
// MAINDEC: decodificador principal. Tabela verdade opcode -> sinais de controle
//==============================================================================
module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  // 11 bits no total: 1 + 2 + 1 + 1 + 2 + 1 + 2 + 1
  logic [10:0] controls;

  // [CORREÇÃO 1] O original separava apenas 10 bits (sem o Jump no final),
  // então cada sinal pegava o bit errado de 'controls' e Jump ficava sem valor.
  // A ordem aqui TEM que ser idêntica à ordem dos bits nas constantes abaixo.
  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls;

  always_comb
    case(op)
    // Formato: RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
    //
    // RegWrite  : 1 = escreve no banco de registradores
    // ImmSrc    : 00=tipo I, 01=tipo S, 10=tipo B, 11=tipo J
    // ALUSrc    : 0 = SrcB vem de rs2 ; 1 = SrcB vem do imediato
    // MemWrite  : 1 = escreve na memória de dados
    // ResultSrc : 00 = ALUResult, 01 = ReadData (memória), 10 = PC+4
    // Branch    : 1 = é desvio condicional
    // ALUOp     : 00 = soma, 01 = subtração, 10 = decidir por funct3/funct7
    // Jump      : 1 = salto incondicional
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw  (soma base+offset, resultado vem da memória)
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw  (imediato tipo S, escreve na memória)
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type (add, sub, and, or, slt)
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq (imediato tipo B, ALU subtrai p/ comparar)

      // [CORREÇÃO 2] Instruções que estavam faltando:
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // addi / I-type ALU (imediato tipo I, ALUSrc=1)
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal (imediato tipo J, grava PC+4 em rd, Jump=1)

      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // instrução não implementada
    endcase
endmodule


//==============================================================================
// ALUDEC: decodificador da ALU. Converte ALUOp/funct3/funct7 em ALUControl
//==============================================================================
module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

  logic  RtypeSub;
  // sub só existe em R-type (opb5=1) com funct7[5]=1.
  // Em addi (opb5=0) o bit 30 faz parte do imediato, então NÃO pode virar sub.
  assign RtypeSub = funct7b5 & opb5;

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // soma (lw, sw, jal)
      2'b01:                ALUControl = 3'b001; // subtração (beq)
      default: case(funct3) // R-type ou I-type: depende do funct3
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b001; // sub
                          else          
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // não implementado
               endcase
    endcase
endmodule


//==============================================================================
// DATAPATH: caminho de dados (PC, banco de registradores, ALU, muxes)
//==============================================================================
module datapath(input  logic        clk, reset,
                input  logic [1:0]  ResultSrc, 
                input  logic        PCSrc, ALUSrc,
                input  logic        RegWrite,
                input  logic [1:0]  ImmSrc,
                input  logic [2:0]  ALUControl,
                output logic        Zero,
                output logic [31:0] PC,
                input  logic [31:0] Instr,
                output logic [31:0] ALUResult, WriteData,
                input  logic [31:0] ReadData);

  logic [31:0] PCNext, PCPlus4, PCTarget;
  logic [31:0] ImmExt;
  logic [31:0] SrcA, SrcB;
  logic [31:0] Result;

  // ---- lógica do próximo PC ----
  flopr #(32) pcreg(clk, reset, PCNext, PC);     // registrador do PC
  adder       pcadd4(PC, 32'd4, PCPlus4);        // PC + 4 (próxima instrução)
  adder       pcaddbranch(PC, ImmExt, PCTarget); // PC + imediato (alvo de beq/jal)
  mux2 #(32)  pcmux(PCPlus4, PCTarget, PCSrc, PCNext); // escolhe PC+4 ou alvo
 
  // ---- banco de registradores ----
  // rs1 = Instr[19:15], rs2 = Instr[24:20], rd = Instr[11:7]
  // WriteData é a saída rd2 (valor de rs2), usada como dado a escrever no sw
  regfile     rf(clk, RegWrite, Instr[19:15], Instr[24:20], 
                 Instr[11:7], Result, SrcA, WriteData);

  // gerador de imediato: recebe Instr[31:7] e monta o imediato conforme ImmSrc
  extend      ext(Instr[31:7], ImmSrc, ImmExt);

  // ---- ALU ----
  mux2 #(32)  srcbmux(WriteData, ImmExt, ALUSrc, SrcB); // SrcB = rs2 ou imediato
  alu         alu(SrcA, SrcB, ALUControl, ALUResult, Zero);

  // [CORREÇÃO 5] Mux do resultado que volta para o banco de registradores:
  //   00 -> ALUResult  (R-type, addi)
  //   01 -> ReadData   (lw)
  //   10 -> PCPlus4    (jal: rd recebe o endereço de retorno)
  // O original tinha 32'b0 na terceira entrada, então o jal gravava 0 em rd
  // (e o sw final usava o endereço errado).
  mux3 #(32)  resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result);
endmodule


//==============================================================================
// REGFILE: banco de 32 registradores, 2 leituras combinacionais e 1 escrita
//==============================================================================
module regfile(input  logic        clk, 
               input  logic        we3, 
               input  logic [ 4:0] a1, a2, a3, 
               input  logic [31:0] wd3, 
               output logic [31:0] rd1, rd2);

  logic [31:0] rf[31:0];

  // Duas portas de leitura combinacionais (A1/RD1, A2/RD2).
  // Uma porta de escrita síncrona, na borda de subida do clock (A3/WD3/WE3).
  // O registrador x0 é sempre 0.

  always_ff @(posedge clk)
    if (we3) rf[a3] <= wd3;	

  assign rd1 = (a1 != 0) ? rf[a1] : 0;
  assign rd2 = (a2 != 0) ? rf[a2] : 0;
endmodule


//==============================================================================
// ADDER: somador simples de 32 bits
//==============================================================================
module adder(input  [31:0] a, b,
             output [31:0] y);

  assign y = a + b;
endmodule


//==============================================================================
// EXTEND: gerador de imediato (extensão de sinal). Cada tipo de instrução
// guarda o imediato em bits diferentes; aqui ele é remontado em 32 bits.
//==============================================================================
module extend(input  logic [31:7] instr,
              input  logic [1:0]  immsrc,
              output logic [31:0] immext);
 
  always_comb
    case(immsrc) 
      // [CORREÇÃO 4] Faltavam os casos 00 (tipo I) e 10 (tipo B).

      // Tipo I (addi, lw): imm[11:0] = instr[31:20]
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]};

      // Tipo S (sw): imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 

      // Tipo B (beq): imm[12|10:5|4:1|11], bit 0 sempre 0 (múltiplo de 2)
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};

      // Tipo J (jal): imm[20|10:1|11|19:12], bit 0 sempre 0
      2'b11:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; 

      default: immext = 32'bx; // indefinido
    endcase             
endmodule


//==============================================================================
// FLOPR: registrador com reset assíncrono (usado para o PC)
//==============================================================================
module flopr #(parameter WIDTH = 8)
              (input  logic             clk, reset,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;   // reset zera o PC (programa começa no endereço 0)
    else       q <= d;
endmodule


//==============================================================================
// MUX2: multiplexador de 2 entradas (s=0 -> d0, s=1 -> d1)
//==============================================================================
module mux2 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, 
              input  logic             s, 
              output logic [WIDTH-1:0] y);

  assign y = s ? d1 : d0; 
endmodule


//==============================================================================
// MUX3: multiplexador de 3 entradas (00 -> d0, 01 -> d1, 1x -> d2)
//==============================================================================
module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2,
              input  logic [1:0]       s, 
              output logic [WIDTH-1:0] y);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0); 
endmodule


//==============================================================================
// IMEM: memória de instruções (somente leitura).
// O programa de teste (o mesmo do riscvtest.s / riscvtest.txt) está embutido
// aqui, para que este único arquivo .sv funcione sozinho com o testbench.
// Cada posição RAM[i] guarda a instrução do endereço 4*i (PC/4).
//==============================================================================
module imem(input  logic [31:0] a,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  initial
    begin
      //             código de máquina    assembly                  endereço  efeito
      RAM[0]  = 32'h00500113; // addi x2, x0, 5          // 0x00  x2 = 5
      RAM[1]  = 32'h00C00193; // addi x3, x0, 12         // 0x04  x3 = 12
      RAM[2]  = 32'hFF718393; // addi x7, x3, -9         // 0x08  x7 = 3
      RAM[3]  = 32'h0023E233; // or   x4, x7, x2         // 0x0C  x4 = 3 OR 5 = 7
      RAM[4]  = 32'h0041F2B3; // and  x5, x3, x4         // 0x10  x5 = 12 AND 7 = 4
      RAM[5]  = 32'h004282B3; // add  x5, x5, x4         // 0x14  x5 = 4 + 7 = 11
      RAM[6]  = 32'h02728863; // beq  x5, x7, end        // 0x18  não desvia (11 != 3)
      RAM[7]  = 32'h0041A233; // slt  x4, x3, x4         // 0x1C  x4 = (12 < 7) = 0
      RAM[8]  = 32'h00020463; // beq  x4, x0, around     // 0x20  desvia (x4 == 0)
      RAM[9]  = 32'h00000293; // addi x5, x0, 0          // 0x24  (pulada)
      RAM[10] = 32'h0023A233; // slt  x4, x7, x2         // 0x28  x4 = (3 < 5) = 1
      RAM[11] = 32'h005203B3; // add  x7, x4, x5         // 0x2C  x7 = 1 + 11 = 12
      RAM[12] = 32'h402383B3; // sub  x7, x7, x2         // 0x30  x7 = 12 - 5 = 7
      RAM[13] = 32'h0471AA23; // sw   x7, 84(x3)         // 0x34  mem[96] = 7
      RAM[14] = 32'h06002103; // lw   x2, 96(x0)         // 0x38  x2 = mem[96] = 7
      RAM[15] = 32'h005104B3; // add  x9, x2, x5         // 0x3C  x9 = 7 + 11 = 18
      RAM[16] = 32'h008001EF; // jal  x3, end            // 0x40  x3 = 0x44, PC = 0x48
      RAM[17] = 32'h00100113; // addi x2, x0, 1          // 0x44  (pulada)
      RAM[18] = 32'h00910133; // add  x2, x2, x9         // 0x48  x2 = 7 + 18 = 25
      RAM[19] = 32'h0221A023; // sw   x2, 0x20(x3)       // 0x4C  mem[68+32=100] = 25
      RAM[20] = 32'h00210063; // beq  x2, x2, done       // 0x50  loop infinito
    end

  assign rd = RAM[a[31:2]]; // endereço alinhado em palavra: descarta os 2 bits baixos
endmodule


//==============================================================================
// DMEM: memória de dados. Leitura combinacional, escrita síncrona (sw).
//==============================================================================
module dmem(input  logic        clk, we,
            input  logic [31:0] a, wd,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  assign rd = RAM[a[31:2]]; // endereço alinhado em palavra

  always_ff @(posedge clk)
    if (we) RAM[a[31:2]] <= wd;
endmodule


//==============================================================================
// ALU: unidade lógica e aritmética
//   alucontrol: 000 add | 001 sub | 010 and | 011 or
//               100 xor | 101 slt | 110 sll | 111 srl
//==============================================================================
module alu(input  logic [31:0] a, b,
           input  logic [2:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);

  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // verdadeiro quando é soma ou subtração

  // Subtração = a + (~b) + 1: inverte b e usa alucontrol[0] como carry-in
  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum = a + condinvb + alucontrol[0];
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] & alucontrol[0];

  always_comb
    case (alucontrol)
      3'b000:  result = sum;         // add
      3'b001:  result = sum;         // subtract
      3'b010:  result = a & b;       // and
      3'b011:  result = a | b;       // or
      3'b100:  result = a ^ b;       // xor
      3'b101:  result = sum[31] ^ v; // slt (sinal da subtração, corrigido por overflow)
      3'b110:  result = a << b[4:0]; // sll
      3'b111:  result = a >> b[4:0]; // srl
      default: result = 32'bx;
    endcase

  // Zero = 1 quando o resultado é 0 (usado pelo beq: a - b == 0 -> a == b)
  assign zero = (result == 32'b0);
  // Overflow da soma/subtração com sinal
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
  
endmodule
