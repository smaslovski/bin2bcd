--------------------------------------------------------------------------------
-- Testbench for BIN2BCD converter with ready/valid handshake interface.
-- Author: Stanislav Maslovski <stanislav.maslovski@gmail.com>
-- Initial testbench template was generated with ChatGPT.
-- This code is in public domain, use freely.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_bin2bcd is
end entity tb_bin2bcd;

architecture tb of tb_bin2bcd is

  constant width      : positive := 16;
  constant bcd_width  : positive := 20;
  constant clk_period : time     := 10 ns;
  constant num_tests  : positive := 50000;

  constant in_probability    : real := 0.7;
  constant stall_probability : real := 0.5;
  constant max_delay         : real := 20.0; -- clock periods

  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';

  signal i_valid : std_ulogic := '0';
  signal i_ready : std_ulogic := '0';
  signal o_valid : std_ulogic;
  signal o_ready : std_ulogic;

  signal i_bin : std_ulogic_vector (width-1 downto 0) := (others => '0');
  signal o_bcd : std_ulogic_vector (bcd_width-1 downto 0);

  ------------------------------------------------------------------
  -- transaction type
  ------------------------------------------------------------------

  type txn_t is record
    bin   : std_ulogic_vector (width-1 downto 0);
    bcd   : std_ulogic_vector (bcd_width-1 downto 0);
    cycle : natural;
  end record;

  type scoreboard_t is array (0 to num_tests) of txn_t;
  shared variable send_board, recv_board : scoreboard_t;
  shared variable wr_ptr, rd_ptr : natural := 0;

  ------------------------------------------------------------------
  -- statistics
  ------------------------------------------------------------------

  signal cycle_counter : natural := 0;
  signal finish : boolean := false;

  ------------------------------------------------------------------
  -- reference bin to bcd conversion
  ------------------------------------------------------------------

  function to_bcd(n : std_ulogic_vector) return std_ulogic_vector is

    variable num       : unsigned(n'range) := unsigned(n);
    variable quotient  : unsigned(n'range);
    variable remainder : natural;

    variable digit  : natural;
    variable result : std_ulogic_vector(bcd_width-1 downto 0) := (others => '0');

  begin

    for d in 0 to bcd_width/4-1 loop

      quotient  := (others => '0');
      remainder := 0;

      -- divide num by 10 using binary long division
      for i in num'range loop
        remainder := remainder * 2 + to_integer(num(i downto i));

        if remainder >= 10 then
          quotient(i) := '1';
          remainder := remainder - 10;
        else
          quotient(i) := '0';
        end if;
      end loop;

      digit := remainder;

      result(4*d+3 downto 4*d) :=
        std_ulogic_vector(to_unsigned(digit,4));

      num := quotient;

      exit when num = 0;

    end loop;

    return result;

  end function;

  ------------------------------------------------------------------
  -- converting BCD to BIN
  ------------------------------------------------------------------

  function to_bin(bcd : std_ulogic_vector) return std_ulogic_vector is

    constant digits : natural := bcd'length/4;

    variable result : unsigned(width-1 downto 0) := (others => '0');
    variable digit  : unsigned(3 downto 0);

  begin

    for i in digits-1 downto 0 loop

      -- multiply current result by 10
      result := (result sll 3) + (result sll 1);

      -- extract BCD digit
      digit := unsigned(bcd(4*i+3 downto 4*i));

      -- add digit
      result := result + resize(digit, result'length);

    end loop;

    return std_ulogic_vector(result);

  end function;

  ------------------------------------------------------------------
  -- converting binary to string in arbitrary radix
  ------------------------------------------------------------------

   function to_string_radix(value : std_ulogic_vector; radix : natural) return string is

    constant digits : string := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    constant len : natural := natural(ceil(real(value'length)*log(2.0)/log(real(radix))));

    variable num       : unsigned(value'range) := unsigned(value);
    variable quotient  : unsigned(value'range);
    variable remainder : natural;

    variable tmp       : string(1 to len) := (others => '0');
    variable pos       : integer := tmp'right + 1;

  begin

    if radix < 2 or radix > digits'length then
      report "Radix out of range" severity failure;
    end if;

    if num = 0 then
      return "0";
    end if;

    -- repeated division
    while num /= 0 loop

      quotient  := (others => '0');
      remainder := 0;

      -- divide num by radix
      for i in num'range loop
        remainder := remainder * 2 + to_integer(num(i downto i));

        if remainder >= radix then
          quotient(i) := '1';
          remainder := remainder - radix;
        else
          quotient(i) := '0';
        end if;
      end loop;

      pos := pos - 1;
      tmp(pos) := digits(remainder + 1);

      num := quotient;

    end loop;

    return tmp(1 to tmp'right);

  end function;

  ------------------------------------------------------------------
  -- DUT
  ------------------------------------------------------------------

begin

  uut : entity work.bin2bcd
    generic map (
      width => width,
      bcd_width => bcd_width
    )
    port map (
      i_clk   => clk,
      i_rst   => rst,
      i_valid => i_valid,
      i_ready => i_ready,
      i_bin   => i_bin,
      o_bcd   => o_bcd,
      o_ready => o_ready,
      o_valid => o_valid
    );

  ------------------------------------------------------------------
  -- clock generation
  ------------------------------------------------------------------

  clock_proc : process is
  begin

    while not finish loop
      wait for clk_period/2;
      clk <= not clk;
    end loop;

    wait;

  end process;

  ------------------------------------------------------------------
  -- reset generation
  ------------------------------------------------------------------

  reset_proc : process
  begin

    rst <= '1';

    wait for 4 * clk_period;
    wait until falling_edge(clk);

    rst <= '0';

    wait;

  end process;

  ------------------------------------------------------------------
  -- cycle counter
  ------------------------------------------------------------------

  clk_cnt_proc : process (clk) is
  begin

    if rising_edge(clk) then
      cycle_counter <= cycle_counter + 1;
    end if;

  end process;

  ------------------------------------------------------------------
  -- random output backpressure
  ------------------------------------------------------------------

  backpressure_proc : process is

    variable seed1 : positive := 154;
    variable seed2 : positive := 231;
    variable r     : real;
    variable delay : natural;

  begin

    i_ready <= '1';

    wait until rst = '0';

    while not finish loop

      wait until rising_edge(clk);

      uniform(seed1, seed2, r);

      if r < stall_probability then
        i_ready <= '0';
      else
        i_ready <= '1';
      end if;

      uniform(seed1, seed2, r);
      delay := integer(r * max_delay) + 1;
      wait for delay * clk_period;

    end loop;

    wait;

  end process;

  ------------------------------------------------------------------
  -- stimulus
  ------------------------------------------------------------------

  stimulus_proc : process

    variable seed1 : positive := 101;
    variable seed2 : positive := 77;
    variable r     : real;

    variable rand_int : natural;
    variable txn      : txn_t;

  begin

    wait until rst = '0';
    wait until rising_edge(clk);

    while wr_ptr < num_tests loop

      i_valid <= '0';

      ----------------------------------------------------------------
      -- drive input
      ----------------------------------------------------------------

      uniform(seed1, seed2, r);

      if r < in_probability then

        ----------------------------------------------------------------
        -- generate transaction
        ----------------------------------------------------------------

        uniform(seed1, seed2, r);
        rand_int := natural(r * real(2**width-1));

        i_bin   <= std_ulogic_vector(to_unsigned(rand_int,width));
        i_valid <= '1';

        ----------------------------------------------------------------
        -- wait for handshake
        ----------------------------------------------------------------

        wait until rising_edge(clk) and o_ready = '1';

        ----------------------------------------------------------------
        -- transaction accepted
        ----------------------------------------------------------------

        txn.bin   := i_bin;
        txn.bcd   := to_bcd(i_bin);
        txn.cycle := cycle_counter;

        send_board(wr_ptr) := txn;

        wr_ptr := wr_ptr + 1;

        report "INPUT:  " & to_string_radix(i_bin,2)
               & " = " & to_string_radix(txn.bcd,16)
               & " at " & natural'image(cycle_counter) & " cycle";

      end if;

    end loop;

    i_valid <= '0';

    wait;

  end process;

  ------------------------------------------------------------------
  -- consumer
  ------------------------------------------------------------------

  consumer_proc : process is

    variable txn : txn_t;

  begin

    while rd_ptr < num_tests loop

      wait until rising_edge(clk);

      if o_valid = '1' and i_ready = '1' then

        txn.bin   := to_bin(o_bcd);
        txn.bcd   := o_bcd;
        txn.cycle := cycle_counter;
        recv_board(rd_ptr) := txn;

        rd_ptr := rd_ptr + 1;

        report "OUTPUT: " & to_string_radix(o_bcd,16)
               & " = " & to_string_radix(txn.bin,2)
               & " at " & natural'image(cycle_counter) & " cycle";

      end if;

    end loop;

    finish <= true after 10*clk_period;

    wait;

  end process;

  check : process is
    variable mismatches : natural := 0;
  begin

    wait until finish;

    for i in 0 to num_tests-1 loop
      if recv_board(i).bcd /= send_board(i).bcd then

        mismatches := mismatches + 1;
        report "BCD mismatch " & to_string_radix(recv_board(i).bcd,16)
               & " for input " & to_string_radix(send_board(i).bin,10)
               & " at " & natural'image(recv_board(i).cycle) & " cycle" severity error;

      end if;
    end loop;

    report "--------------------------------";
    report "TEST COMPLETE";
    report "Transactions = " & natural'image(wr_ptr);
    report "Errors       = " & natural'image(mismatches);
    report "--------------------------------";

    wait;

  end process;

end architecture tb;
