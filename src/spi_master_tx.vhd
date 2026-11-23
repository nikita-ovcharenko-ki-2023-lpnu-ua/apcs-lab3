--------------------------------------------------------------------------------
-- spi_master_tx.vhd
-- SPI master transmitter and serial clock generator.
--
-- The module owns the bus timing of an SPI master: it divides the system clock
-- to produce SCLK, drives the active-low slave select SS_n and shifts the
-- transmit word out on MOSI, MSB first. It also tells the receiver
-- (spi_master_rx) in which system-clock cycle MISO must be sampled.
--
-- All four SPI modes are supported through the generics G_CPOL / G_CPHA:
--   mode | CPOL | CPHA | SCLK idle | MISO/MOSI sampled on | data changes on
--   -----+------+------+-----------+----------------------+----------------
--    0   |  0   |  0   |   low     | rising  (leading)    | falling (trailing)
--    1   |  0   |  1   |   low     | falling (trailing)   | rising  (leading)
--    2   |  1   |  0   |   high    | falling (leading)    | rising  (trailing)
--    3   |  1   |  1   |   high    | rising  (trailing)   | falling (leading)
--
-- Timing: one SCLK half-period = G_CLK_DIV system clock cycles, so
--   f_SCLK = f_clk / (2 * G_CLK_DIV).
-- SS_n is asserted one half-period before the first SCLK edge (setup) and
-- released one half-period after the last edge (hold).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_master_tx is
  generic (
    G_DATA_WIDTH : positive  := 8;    -- bits per transfer
    G_CLK_DIV    : positive  := 4;    -- system clock cycles per SCLK half-period
    G_CPOL       : std_logic := '0';  -- SCLK idle level
    G_CPHA       : std_logic := '0'   -- '0': sample on leading edge, '1': on trailing edge
  );
  port (
    i_clk    : in  std_logic;                                   -- system clock
    i_rst    : in  std_logic;                                   -- synchronous reset, active high
    i_start  : in  std_logic;                                   -- 1-cycle request to start a transfer (ignored while busy)
    i_data   : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- word to transmit, captured on i_start
    o_busy   : out std_logic;                                   -- '1' from i_start until o_done
    o_done   : out std_logic;                                   -- 1-cycle pulse: transfer finished, SS_n released
    o_sample : out std_logic;                                   -- 1-cycle strobe for the receiver: sample MISO now
    o_sclk   : out std_logic;                                   -- SPI serial clock
    o_mosi   : out std_logic;                                   -- SPI master out / slave in
    o_ss_n   : out std_logic                                    -- SPI slave select, active low
  );
end entity spi_master_tx;

architecture rtl of spi_master_tx is

  -- Transmitter FSM (see docs/fsm.md)
  type t_state is (S_IDLE, S_SETUP, S_TRANSFER, S_HOLD, S_DONE);
  signal state : t_state := S_IDLE;

  -- Clock divider: counts system clock cycles inside one SCLK half-period.
  signal div_cnt  : natural range 0 to G_CLK_DIV - 1 := 0;
  -- SCLK edges generated so far in the current transfer (2 per bit).
  signal edge_cnt : natural range 0 to 2 * G_DATA_WIDTH := 0;
  -- Index of the bit currently driven on MOSI (MSB first).
  signal bit_idx  : natural range 0 to G_DATA_WIDTH - 1 := G_DATA_WIDTH - 1;
  -- Transmit word latched at the start of a transfer.
  signal tx_reg   : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- Registered outputs
  signal sclk_r   : std_logic := G_CPOL;
  signal mosi_r   : std_logic := '0';
  signal ss_n_r   : std_logic := '1';
  signal done_r   : std_logic := '0';
  signal sample_r : std_logic := '0';

  -- '1' in the last system-clock cycle of an SCLK half-period.
  signal tick : std_logic;

begin

  tick <= '1' when div_cnt = G_CLK_DIV - 1 else '0';

  ------------------------------------------------------------------------------
  -- Main sequential process: FSM, clock divider, SCLK and MOSI generation.
  ------------------------------------------------------------------------------
  p_fsm : process (i_clk)
    variable leading : boolean;  -- the SCLK edge generated now is the first edge of a bit
  begin
    if rising_edge(i_clk) then
      done_r   <= '0';
      sample_r <= '0';

      if i_rst = '1' then
        state    <= S_IDLE;
        div_cnt  <= 0;
        edge_cnt <= 0;
        bit_idx  <= G_DATA_WIDTH - 1;
        sclk_r   <= G_CPOL;
        mosi_r   <= '0';
        ss_n_r   <= '1';
      else
        -- free-running divider, restarted in IDLE so every transfer has the same timing
        if state = S_IDLE or tick = '1' then
          div_cnt <= 0;
        else
          div_cnt <= div_cnt + 1;
        end if;

        case state is

          -- Bus idle: SS_n high, SCLK at its idle level. Wait for i_start.
          when S_IDLE =>
            sclk_r <= G_CPOL;
            ss_n_r <= '1';
            if i_start = '1' then
              tx_reg   <= i_data;
              bit_idx  <= G_DATA_WIDTH - 1;
              edge_cnt <= 0;
              ss_n_r   <= '0';
              -- CPHA = 0: the first bit must be valid before the first (sampling) edge
              if G_CPHA = '0' then
                mosi_r <= i_data(G_DATA_WIDTH - 1);
              end if;
              state <= S_SETUP;
            end if;

          -- SS_n asserted, wait one SCLK half-period (slave setup time).
          when S_SETUP =>
            if tick = '1' then
              state <= S_TRANSFER;
            end if;

          -- Generate 2 * G_DATA_WIDTH SCLK edges; shift and sample on them.
          when S_TRANSFER =>
            if tick = '1' then
              if edge_cnt = 2 * G_DATA_WIDTH then
                state <= S_HOLD;               -- all edges done, SCLK is back at idle level
              else
                sclk_r   <= not sclk_r;
                edge_cnt <= edge_cnt + 1;
                leading  := (edge_cnt mod 2) = 0;

                if G_CPHA = '0' then
                  if leading then
                    sample_r <= '1';           -- receiver samples MISO on the leading edge
                  elsif bit_idx > 0 then
                    mosi_r  <= tx_reg(bit_idx - 1);  -- next bit on the trailing edge
                    bit_idx <= bit_idx - 1;
                  end if;
                else
                  if leading then
                    mosi_r <= tx_reg(bit_idx); -- drive the bit on the leading edge
                  else
                    sample_r <= '1';           -- receiver samples MISO on the trailing edge
                    if bit_idx > 0 then
                      bit_idx <= bit_idx - 1;
                    end if;
                  end if;
                end if;
              end if;
            end if;

          -- SCLK idle, SS_n still asserted for one half-period (slave hold time).
          when S_HOLD =>
            if tick = '1' then
              ss_n_r <= '1';
              done_r <= '1';
              state  <= S_DONE;
            end if;

          -- One cycle with SS_n released before a new transfer may start.
          when S_DONE =>
            state <= S_IDLE;

        end case;
      end if;
    end if;
  end process p_fsm;

  o_sclk   <= sclk_r;
  o_mosi   <= mosi_r;
  o_ss_n   <= ss_n_r;
  o_done   <= done_r;
  o_sample <= sample_r;
  o_busy   <= '0' when state = S_IDLE else '1';

end architecture rtl;
