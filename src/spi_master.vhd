--------------------------------------------------------------------------------
-- spi_master.vhd
-- Full-duplex SPI master = transmitter (spi_master_tx) + receiver (spi_master_rx).
--
-- Usage: put the word to send on i_tx_data and pulse i_start for one clock
-- while o_busy = '0'. The master asserts SS_n, generates G_DATA_WIDTH SCLK
-- periods, shifts i_tx_data out on MOSI and, at the same time, shifts the
-- slave's reply in from MISO. When o_done pulses, SS_n is released and
-- o_rx_data holds the received word (o_rx_valid pulsed a little earlier,
-- right after the last bit was sampled).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_master is
  generic (
    G_DATA_WIDTH : positive  := 8;    -- bits per transfer
    G_CLK_DIV    : positive  := 4;    -- f_SCLK = f_clk / (2 * G_CLK_DIV)
    G_CPOL       : std_logic := '0';  -- SPI clock polarity
    G_CPHA       : std_logic := '0'   -- SPI clock phase
  );
  port (
    -- system side
    i_clk      : in  std_logic;
    i_rst      : in  std_logic;
    i_start    : in  std_logic;
    i_tx_data  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    o_rx_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    o_rx_valid : out std_logic;
    o_busy     : out std_logic;
    o_done     : out std_logic;
    -- SPI bus
    o_sclk     : out std_logic;
    o_mosi     : out std_logic;
    i_miso     : in  std_logic;
    o_ss_n     : out std_logic
  );
end entity spi_master;

architecture rtl of spi_master is

  signal sample    : std_logic;  -- tx -> rx: sample MISO in this cycle
  signal start_ack : std_logic;  -- start accepted (master was idle)
  signal busy      : std_logic;

begin

  start_ack <= i_start and not busy;

  u_tx : entity work.spi_master_tx
    generic map (
      G_DATA_WIDTH => G_DATA_WIDTH,
      G_CLK_DIV    => G_CLK_DIV,
      G_CPOL       => G_CPOL,
      G_CPHA       => G_CPHA
    )
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_start  => start_ack,
      i_data   => i_tx_data,
      o_busy   => busy,
      o_done   => o_done,
      o_sample => sample,
      o_sclk   => o_sclk,
      o_mosi   => o_mosi,
      o_ss_n   => o_ss_n
    );

  u_rx : entity work.spi_master_rx
    generic map (
      G_DATA_WIDTH => G_DATA_WIDTH
    )
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_start  => start_ack,
      i_sample => sample,
      i_miso   => i_miso,
      o_data   => o_rx_data,
      o_valid  => o_rx_valid
    );

  o_busy <= busy;

end architecture rtl;
