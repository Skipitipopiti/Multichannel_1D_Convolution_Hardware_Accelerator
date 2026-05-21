package DP_package;
    //4 elementi da 8 bit ciascuno 
    typedef struct packed {
        logic signed [3:0][7:0] o; 
    } Bus4B_t;

    //5 elementi da 8 bit ciascuno
    typedef struct packed {
        logic signed [4:0][7:0] o;
    } Bus5B_t;
endpackage