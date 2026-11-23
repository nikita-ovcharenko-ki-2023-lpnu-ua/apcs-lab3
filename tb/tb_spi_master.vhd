--------------------------------------------------------------------------------
-- tb_spi_master.vhd
-- Self-checking testbench for spi_master in all four SPI modes.
--
-- For every mode (CPOL, CPHA) the testbench instantiates:
--   * the device under test (spi_master);
--   * a behavioural SPI slave model that samples MOSI and drives MISO on the
--     edges defined by the mode, i.e. it imitates the "other device";
--   * a protocol monitor that checks the SCLK idle level and the number of
--     SCLK edges per transfer.
-- A stimulus process generates reset, sends a list of test words and checks
-- that (a) the slave received exactly what the master transmitted on MOSI and
-- (b) the master received exactly what the slave transmitted on MISO.
--
-- The simulation ends with "TB RESULT: PASS" or "TB RESULT: FAIL" and a
-- non-zero exit code on failure.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_spi_master is
end entity tb_spi_master;

architecture sim of tb_spi_master is

  constant C_CLK_PERIOD : time     := 20 ns;  -- 50 MHz system clock
  constant C_WIDTH      : positive := 8;
  constant C_CLK_DIV    : positive := 4;      -- f_SCLK = 50 MHz / 8 = 6.25 MHz

  type t_words is array (natural range <>) of std_logic_vector(C_WIDTH - 1 downto 0);
  -- words the master sends (MOSI) and the slave answers (MISO)
  constant C_MASTER_WORDS : t_words := (x"A5", x"3C", x"FF", x"00", x"81", x"5A", x"C3");
  constant C_SLAVE_WORDS  : t_words := (x"5A", x"C3", x"00", x"FF", x"7E", x"96", x"E1");

  constant C_MODES : natural := 4;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  type t_sl_array is array (0 to C_MODES - 1) of std_logic;
  type t_nat_array is array (0 to C_MODES - 1) of natural;
  signal finished : t_sl_array := (others => '0');  -- per-mode test sequence finished
  signal errors   : t_nat_array := (others => 0);   -- per-mode error count

  function to_hex(v : std_logic_vector) return string is
  begin
    return to_hstring(v);
  end function;

  -- SPI mode number -> CPOL / CPHA
  function mode_cpol(m : natural) return std_logic is
  begin
    if m >= 2 then return '1'; else return '0'; end if;
  end function;

  function mode_cpha(m : natural) return std_logic is
  begin
    if m mod 2 = 1 then return '1'; else return '0'; end if;
  end function;

  function all_set(v : t_sl_array) return boolean is
  begin
    for i in v'range loop
      if v(i) /= '1' then return false; end if;
    end loop;
    return true;
  end function;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

  g_mode : for m in 0 to C_MODES - 1 generate
    constant C_CPOL : std_logic := mode_cpol(m);
    constant C_CPHA : std_logic := mode_cpha(m);

    signal start, busy, done, rx_valid : std_logic := '0';
    signal tx_data, rx_data            : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
    signal sclk, mosi, miso, ss_n      : std_logic;

    -- word received by the slave model in the last transfer
    signal slave_rx       : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
    signal slave_rx_ready : std_logic := '0';
    -- index of the reply the slave is currently sending
    signal slave_idx      : natural := 0;
    -- protocol monitor counters
    signal edge_count     : natural := 0;
    signal mon_errors     : natural := 0;
  begin

    ----------------------------------------------------------------------------
    -- Device under test
    ----------------------------------------------------------------------------
    u_dut : entity work.spi_master
      generic map (
        G_DATA_WIDTH => C_WIDTH,
        G_CLK_DIV    => C_CLK_DIV,
        G_CPOL       => C_CPOL,
        G_CPHA       => C_CPHA
      )
      port map (
        i_clk      => clk,
        i_rst      => rst,
        i_start    => start,
        i_tx_data  => tx_data,
        o_rx_data  => rx_data,
        o_rx_valid => rx_valid,
        o_busy     => busy,
        o_done     => done,
        o_sclk     => sclk,
        o_mosi     => mosi,
        i_miso     => miso,
        o_ss_n     => ss_n
      );

    ----------------------------------------------------------------------------
    -- Behavioural SPI slave: samples MOSI and drives MISO, MSB first.
    -- Leading edge = first SCLK edge of a bit (rising if CPOL = 0).
    ----------------------------------------------------------------------------
    p_slave : process
      variable tx_word : std_logic_vector(C_WIDTH - 1 downto 0);
      variable rx_word : std_logic_vector(C_WIDTH - 1 downto 0);
    begin
      miso <= 'Z';
      wait until falling_edge(ss_n);
      tx_word := C_SLAVE_WORDS(slave_idx);
      slave_rx_ready <= '0';
      if C_CPHA = '0' then
        miso <= tx_word(C_WIDTH - 1);           -- first bit valid before the first edge
      end if;
      for b in C_WIDTH - 1 downto 0 loop
        -- leading edge
        wait until sclk'event and sclk = not C_CPOL;
        if C_CPHA = '0' then
          rx_word(b) := mosi;                   -- sample on leading edge
        else
          miso <= tx_word(b);                   -- shift out on leading edge
        end if;
        -- trailing edge
        wait until sclk'event and sclk = C_CPOL;
        if C_CPHA = '0' then
          if b > 0 then
            miso <= tx_word(b - 1);             -- shift out on trailing edge
          end if;
        else
          rx_word(b) := mosi;                   -- sample on trailing edge
        end if;
      end loop;
      wait until rising_edge(ss_n);
      slave_rx       <= rx_word;
      slave_rx_ready <= '1';
      slave_idx      <= slave_idx + 1;
    end process p_slave;

    ----------------------------------------------------------------------------
    -- Protocol monitor: SCLK idle level and edges per transfer.
    ----------------------------------------------------------------------------
    p_monitor : process (sclk, ss_n, rst)
    begin
      if rst = '1' then
        null;                                   -- ignore initialisation (U -> 0/1) and reset
      elsif falling_edge(ss_n) then
        edge_count <= 0;
        if sclk /= C_CPOL then
          report "mode " & integer'image(m) & ": SCLK not at idle level when SS_n asserted" severity error;
          mon_errors <= mon_errors + 1;
        end if;
      elsif sclk'event and ss_n = '0' then
        edge_count <= edge_count + 1;
      elsif rising_edge(ss_n) then
        if edge_count /= 2 * C_WIDTH then
          report "mode " & integer'image(m) & ": " & integer'image(edge_count) &
                 " SCLK edges, expected " & integer'image(2 * C_WIDTH) severity error;
          mon_errors <= mon_errors + 1;
        end if;
      elsif sclk'event and ss_n = '1' then
        report "mode " & integer'image(m) & ": SCLK toggled while SS_n is high" severity error;
        mon_errors <= mon_errors + 1;
      end if;
    end process p_monitor;

    ----------------------------------------------------------------------------
    -- Stimulus and checks
    ----------------------------------------------------------------------------
    p_stim : process
      variable err : natural := 0;
    begin
      wait until rst = '0';
      wait until rising_edge(clk);

      for i in C_MASTER_WORDS'range loop
        -- start a transfer
        tx_data <= C_MASTER_WORDS(i);
        start   <= '1';
        wait until rising_edge(clk);
        start   <= '0';
        tx_data <= (others => 'X');             -- the master must have latched the word
        wait until rising_edge(clk) and done = '1';
        if slave_rx_ready /= '1' then
          wait until slave_rx_ready = '1' for 1 us;
        end if;

        -- MOSI path: slave received what the master sent
        if slave_rx /= C_MASTER_WORDS(i) then
          report "mode " & integer'image(m) & ", word " & integer'image(i) & ": slave got 0x" &
                 to_hex(slave_rx) & ", expected 0x" & to_hex(C_MASTER_WORDS(i)) severity error;
          err := err + 1;
        end if;
        -- MISO path: master received what the slave sent
        if rx_data /= C_SLAVE_WORDS(i) then
          report "mode " & integer'image(m) & ", word " & integer'image(i) & ": master got 0x" &
                 to_hex(rx_data) & ", expected 0x" & to_hex(C_SLAVE_WORDS(i)) severity error;
          err := err + 1;
        end if;
        report "mode " & integer'image(m) & " (CPOL=" & std_logic'image(C_CPOL) & ", CPHA=" &
               std_logic'image(C_CPHA) & ") word " & integer'image(i) & ": MOSI 0x" &
               to_hex(C_MASTER_WORDS(i)) & " -> slave 0x" & to_hex(slave_rx) & ", MISO 0x" &
               to_hex(C_SLAVE_WORDS(i)) & " -> master 0x" & to_hex(rx_data) severity note;

        -- the last two words are sent back-to-back, the others with a pause
        if i < C_MASTER_WORDS'high - 1 then
          wait for 300 ns;
        end if;
      end loop;

      wait for 200 ns;
      errors(m)   <= err + mon_errors;
      finished(m) <= '1';
      wait;
    end process p_stim;

  end generate g_mode;

  ------------------------------------------------------------------------------
  -- Reset and final verdict
  ------------------------------------------------------------------------------
  p_main : process
    variable total : natural := 0;
  begin
    rst <= '1';
    wait for 5 * C_CLK_PERIOD;
    rst <= '0';

    wait until all_set(finished) for 200 us;
    for m in 0 to C_MODES - 1 loop
      if finished(m) /= '1' then
        report "mode " & integer'image(m) & ": test sequence did not finish (timeout)" severity error;
        total := total + 1;
      end if;
      total := total + errors(m);
    end loop;

    if total = 0 then
      report "TB RESULT: PASS (" & integer'image(C_MODES * C_MASTER_WORDS'length) &
             " transfers in 4 SPI modes, MOSI and MISO checked)" severity note;
      finish;
    else
      report "TB RESULT: FAIL, " & integer'image(total) & " error(s)" severity failure;
    end if;
    wait;
  end process p_main;

end architecture sim;
