package tc32v_pkg;
    typedef logic [3:0][7:0] word_t;
    
    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_ORR,
        ALU_XOR,
        ALU_SLT,
        ALU_SLTU,
        ALU_SLL,
        ALU_SRL,
        ALU_SRA
    } alu_op_t;

    typedef logic [4:0] reg_index_t;
endpackage
