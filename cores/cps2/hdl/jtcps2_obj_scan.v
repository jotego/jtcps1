/*  This file is part of JTCPS1.
    JTCPS1 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCPS1 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCPS1.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 24-1-2021 */


module jtcps2_obj_scan(
    input              rst,
    input              clk,
    input              flip,

    input      [ 8:0]  vrender1, // 2 lines ahead of vdump
    input      [ 8:0]  hdump,
    output reg         line,

    input      [ 9:0]  off_x,
    input      [ 9:0]  off_y,

    // interface with frame table
    output reg [ 9:0]  table_addr,
    input      [15:0]  table_x,
    input      [15:0]  table_y,
    input      [15:0]  table_code,
    input      [15:0]  table_attr,

    // interface with renderer
    output reg         dr_start,    // dr for "draw"
    input              dr_idle,

    output reg [15:0]  dr_code,
    output reg [15:0]  dr_attr,
    output reg [ 8:0]  dr_hpos,
    output reg [ 2:0]  dr_prio,
    output reg [ 1:0]  dr_bank
);

reg  [ 9:0] mapper_in;
reg  [ 8:0] vrenderf;

reg  [ 9:0] obj_y, obj_x;
wire [15:0] code_mn;
wire [ 9:0] st4_effx;
wire [ 1:0] st4_bank;
reg  [ 2:0] st3_prio, st4_prio;
wire        start;

reg         done, last_drstart;
wire [ 3:0] st3_tile_n, st4_tile_n, st3_tile_m;
reg  [ 3:0] npos;  // tile expansion n==horizontal, m==vertical
reg  [ 4:0] n;
wire [ 3:0] subn;
wire [ 3:0] st4_vsub;
wire        inzone, inzonex, st3_vflip;
reg  [ 2:0] wait_cycle;
reg         last_tile;
reg         last_start;
wire        stall, nstall;
reg         cen=0;

reg  [15:0] st3_x, st4_x, st3_y, st4_y,
            st3_code, st3_attr, st4_attr;
reg  [ 3:0] st5_tile_n;

jtcps1_obj_tile_match u_tile_match(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .cen        ( ~stall & cen    ),

    .obj_code   ( st3_code   ),
    .tile_m     ( st3_tile_m ),
    .tile_n     ( st3_tile_n ),
    .n          ( 4'd0       ),

    .vflip      ( st3_vflip  ),
    .vrenderf   ( vrenderf   ),
    .obj_y      ( st3_y[9:0] ),

    .vsub       ( st4_vsub   ),
    .inzone     ( inzone     ),
    .code_mn    ( code_mn    )
);

assign      start      = hdump == 'h1d0;

assign      st3_tile_m = st3_attr[15:12];
assign      st3_tile_n = st3_attr[11: 8];
assign      st3_vflip  = st3_attr[6];

assign      st4_bank   = st4_y[14:13];
assign      st4_tile_n = st4_attr[11: 8];
wire        st4_hflip  = st4_attr[5];
assign      subn       = (st4_hflip ? ( st4_tile_n - n[3:0] ) : n[3:0]);
assign      st4_effx   = st4_x + { 1'b0, subn, 4'd0}; // effective x value for multi tile objects
assign      inzonex    = inzone & ~st4_effx[9];
assign      nstall     = n<=st4_tile_n && st4_tile_n!=0;
assign      stall      = (inzonex && (!dr_idle || nstall)) || dr_start || last_drstart;

reg last_inzone;

always @(posedge clk) cen <= ~cen;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        table_addr <= 0;
        n          <= 0;
        npos       <= 0;
        dr_start   <= 0;
        dr_code    <= 0;
        dr_attr    <= 0;
        dr_hpos    <= 0;
        dr_prio    <= 0;
        last_start <= 0;
        line       <= 0;
        done       <= 1;

        st3_x      <= 0;
        st4_x      <= 0;
        st3_y      <= 0;
        st4_y      <= 0;
        st3_code   <= 0;
        st3_attr   <= 0;
        st4_attr   <= 0;
        st5_tile_n <= 0;

        last_drstart <= 0;
    end else if(cen) begin
        last_start <= start;
        last_drstart <= dr_start;
        last_inzone <= inzone;

        // I
        table_addr <= done ? 0 : ((stall|(inzone&~last_inzone)) ? table_addr : (table_addr+1'd1));
        // II
        if( !stall ) begin
            if( table_y[15] || table_attr[15:8]==8'hff || &table_addr ) begin
                done <= 1;
                st3_y<= ~0;
            end else begin
                st3_code <= table_code;
                st3_x    <= table_x[9:0] + 10'h40 - (table_attr[7] ? 10'd0 : off_x);
                st3_y    <= table_y[9:0] + 10'h10 - (table_attr[7] ? 10'd0 : off_y);
                st3_prio <= table_x[15:13];
                st3_attr <= table_attr;
            end
        end
        // III
        // m/n match
        if( !stall ) begin
            st4_attr <= st3_attr;
            st4_x    <= st3_x;
            st4_y    <= st3_y;
            st4_prio <= st3_prio;
        end
        // IV
        if( inzone ) begin
            if( dr_idle && !dr_start && !last_drstart) begin
                dr_attr  <= { 4'd0, st4_vsub, st4_attr[7:0] };
                //dr_code  <= code_mn + subn;
                dr_code  <= code_mn +  n[3:0]; //(st4_hflip ? ( st4_tile_n - n[3:0] ) : n[3:0]);
                dr_hpos  <= st4_effx - 9'd1;
                dr_prio  <= st4_prio;
                dr_bank  <= st4_bank;
                dr_start <= n <= st4_tile_n;
                if( !nstall ) begin
                    n    <= 0;
                    npos <= 0;
                end else begin
                    n    <= n+1'd1;
                    npos <= st4_hflip ? npos-4'd1 : npos+4'd1;
                end
            end else begin
                dr_start <= 0;
            end
        end else begin
            dr_start <= 0;
        end
        // V
        if( !stall ) begin
            st5_tile_n <= st4_tile_n;
        end


        // This must be at the end
        if( start && !last_start ) begin
            line       <= ~line;
            vrenderf   <= vrender1 ^ {1'b0,{8{flip}}};
            n          <= 0;
            npos       <= 0;
            done       <= 0;
            table_addr <= 0;
        end
    end
end

endmodule
