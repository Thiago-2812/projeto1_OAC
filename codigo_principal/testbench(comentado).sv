//==============================================================================
// riscvsingle_p1.sv  --  Processador RISC-V MONOCICLO (Parte 1)
//
// Instruções suportadas: lw, sw, add, sub, and, or, slt, addi, beq, jal
//
// COMPILAR:  iverilog -g2012 -o riscvsingle_p1.vcd -tvvp riscvsingle_p1.sv
// SIMULAR:   vvp riscvsingle_p1
// (o programa de teste já está DENTRO da imem, então não precisa do riscvtest.txt)
//
// Resultado esperado: "Simulation succeeded"  (o programa escreve o valor 25
// no endereço 100 da memória de dados).
//
// -----------------------------------------------------------------------------
// RESUMO DAS CORREÇÕES FEITAS NO CÓDIGO ORIGINAL (marcadas com [CORREÇÃO n]):
//
//  [1] maindec  : o vetor 'controls' tem 11 bits, mas a atribuição só
//                 separava 10 (faltava o sinal Jump). Isso deslocava TODOS os
//                 sinais de controle em 1 bit e deixava Jump sem valor.
//  [2] maindec  : faltavam as instruções addi (opcode 0010011) e
//                 jal (opcode 1101111) na tabela de decodificação.
//  [3] controller: PCSrc = Branch & Zero  ->  PCSrc = (Branch & Zero) | Jump.
//                 Sem o "| Jump", o jal nunca desvia o PC.
//  [4] extend   : faltavam os formatos de imediato tipo I (ImmSrc=00) e
//                 tipo B (ImmSrc=10). Só existiam S (01) e J (11).
//  [5] datapath : o resultmux recebia 32'b0 na entrada 2; deve receber PCPlus4
//                 (o jal grava PC+4 no registrador destino rd).
//  [6] riscvsingle: o fio PCSrc não estava declarado (era criado
//                 implicitamente); agora é declarado explicitamente.
//==============================================================================


//==============================================================================
// TESTBENCH
// Gera clock e reset, instancia o processador (top) e observa as escritas em
// memória. O programa de teste termina escrevendo 25 no endereço 100.
//==============================================================================
module testbench();

  logic        clk;
  logic        reset;

  logic [31:0] WriteData, DataAdr;
  logic        MemWrite;

  // instancia o dispositivo sob teste (processador + memórias)
  top dut(clk, reset, WriteData, DataAdr, MemWrite);
  
  // inicialização: reset ativo por 22 unidades de tempo, depois desativa
  initial
    begin
      reset <= 1; # 22; reset <= 0;
    end

  // gera o clock (período de 10 unidades de tempo)
  always
    begin
      clk <= 1; # 5; clk <= 0; # 5;
    end

  // verifica os resultados na borda de descida do clock
  always @(negedge clk)
    begin
      if(MemWrite) begin
        // sucesso: escreveu 25 no endereço 100
        if(DataAdr === 100 & WriteData === 25) begin
          $display("Simulation succeeded");
          $stop;
        // qualquer outra escrita que não seja no endereço 96 é erro
        // (o programa faz uma escrita "intermediária" de 7 em 96, que é válida)
        end else if (DataAdr !== 96) begin
          $display("Simulation failed");
          $stop;
        end
      end
    end
endmodule
