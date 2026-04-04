-------------------------------------------------------------------------------
-- Double-dabble BIN2BCD converter with a ready/valid handshake interface.
-- Author: Stanislav Maslovski <stanislav.maslovski@gmail.com>
-- This code is in public domain, use freely. Standard compliance: VHDL 93.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin2bcd is
  generic (
    width : positive := 16;
    bcd_width : positive := 20 -- 4*ceil(width*log10(2)), divisible by 4
  );
  port (
    i_rst, i_clk, i_ready, i_valid : in std_ulogic;
    i_bin : in  std_ulogic_vector (width-1 downto 0);
    o_bcd : out std_ulogic_vector (bcd_width-1 downto 0);
    o_ready, o_valid : out std_ulogic
  );
end entity bin2bcd;

-------------------------------------------------------------------------------
-- The following FSM-based design realizes a shift-and-add double-dabble
-- micropipelined architecture with a single accumulator register that stores
-- both BCD and BIN data during conversion and an output buffer register.
--
-- The FSM keeps track of the occupancy of these registers and the state of
-- read/valid handshake signals in order to achive latency of WIDTH clocks
-- and throughtput of one word per WIDTH clocks whenever possible.
--
-- The handshake strategy of this module follows the design rule in which
--
--     READY may depend combinationaly on VALID
--     VALID must not depend on READY (i.e. must be registred)
--
-- That is, the combinational loop is broken on the side of the O_VALID
-- signal. Such a strategy saves one clock period of latency for free, but may
-- slightly affect FMAX of the complete design. All modules in a chain must
-- follow the same design rule or have both O_READY and O_VALID registred.
-------------------------------------------------------------------------------

architecture rtl of bin2bcd is

  type state_t is (IDLE, BUSY, BUF_BUSY, STALL, ACC_STALL);
  subtype cnt_range_t is natural range width-1 downto 0;

  signal conv_state, next_conv_state : state_t;
  signal shift_cnt : cnt_range_t;
  signal load_acc, load_buf, next_o_valid : std_ulogic;
  signal acc, next_acc: unsigned (width + bcd_width - 1 downto 0) := (others => '0');

begin

  io_fsm_comb: process (conv_state, shift_cnt, i_valid, i_ready) is
  begin

    next_conv_state <= conv_state;

    load_acc <= '0';
    load_buf <= '0';

    o_ready <= '0';
    next_o_valid <= '0';

    case conv_state is
      when IDLE => 			-- free acc & free buffer
        o_ready <= '1';
        if i_valid = '1' then
          load_acc <= '1';
          next_conv_state <= BUSY;
        end if;
      when BUSY =>			-- busy acc & free buffer
        if shift_cnt = 0 then
          load_buf <= '1';
          next_o_valid <= '1';
          next_conv_state <= STALL;
          if i_valid = '1' then
            o_ready <= '1';
            load_acc <= '1';
            next_conv_state <= BUF_BUSY;
          end if;
        end if;
      when BUF_BUSY =>			-- busy acc & busy buffer
        next_o_valid <= '1';
        if shift_cnt = 0 then
          next_conv_state <= ACC_STALL;
          if i_ready = '1' then
            load_buf <= '1';
            next_conv_state <= STALL;
          end if;
        elsif i_ready = '1' then
          next_o_valid <= '0';
          next_conv_state <= BUSY;
        end if;
      when STALL =>			-- free acc & busy buffer
        next_o_valid <= '1';
        if i_ready = '1' then
          next_o_valid <= '0';
          next_conv_state <= IDLE;
          if i_valid = '1' then
            o_ready <= '1';
            load_acc <= '1';
            next_conv_state <= BUSY;
          end if;
        elsif i_valid = '1' then
            o_ready <= '1';
            load_acc <= '1';
            next_conv_state <= BUF_BUSY;
        end if;
      when ACC_STALL =>			-- busy acc & busy buffer
        next_o_valid <= '1';
        if i_ready = '1' then
          load_buf <= '1';
          next_conv_state <= STALL;
          if i_valid = '1' then
            o_ready <= '1';
            load_acc <= '1';
            next_conv_state <= BUF_BUSY;
          end if;
        end if;
    end case;

  end process io_fsm_comb;

  io_fsm_ff: process (i_clk, i_rst) is
  begin

    if i_rst = '1' then
      conv_state <= IDLE;
    elsif rising_edge(i_clk) then
      if load_buf = '1' then
        o_bcd <= std_ulogic_vector(next_acc(acc'left downto width));
      end if;
      o_valid <= next_o_valid;
      conv_state <= next_conv_state;
    end if;

  end process io_fsm_ff;

  dd_comb: process (acc) is
    variable tmp : unsigned (0 to width + bcd_width - 1);
  begin
    tmp := acc;
    for i in 0 to bcd_width/4-1 loop
      if tmp(4*i to 4*i+3) > 4 then
        tmp(4*i to 4*i+3) := tmp(4*i to 4*i+3) + 3;
      end if;
    end loop;
    next_acc <= shift_left(tmp, 1);
  end process dd_comb;

  dd_seq: process (i_clk, i_rst) is
  begin
    if i_rst = '1' then
      shift_cnt <= 0;
    elsif rising_edge(i_clk) then
      if load_acc = '1' then
        acc <= resize(unsigned(i_bin), acc'length);
        shift_cnt <= width-1;
      elsif shift_cnt /= 0 then
        acc <= next_acc;
        shift_cnt <= shift_cnt - 1;
      end if;
    end if;
  end process dd_seq;

end architecture rtl;
