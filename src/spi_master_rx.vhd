--------------------------------------------------------------------------------
-- spi_master_rx.vhd
-- SPI master receiver.
--
-- Collects the word sent by the slave on MISO. It has no timing logic of its
-- own: the transmitter (spi_master_tx) generates SCLK and raises i_sample in
-- exactly the system-clock cycle in which the sampling SCLK edge is produced
-- (leading edge for CPHA = 0, trailing edge for CPHA = 1). The slave changes
-- MISO half an SCLK period earlier, so MISO is stable when it is sampled.
--
-- Bits arrive MSB first and are shifted in from the right. After
-- G_DATA_WIDTH samples the word is copied to o_data and o_valid pulses.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_master_rx is
  generic (
    G_DATA_WIDTH : positive := 8                                -- bits per transfer
  );
  port (
    i_clk    : in  std_logic;                                   -- system clock
    i_rst    : in  std_logic;                                   -- synchronous reset, active high
    i_start  : in  std_logic;                                   -- new transfer: clear the bit counter
    i_sample : in  std_logic;                                   -- strobe from the transmitter: sample MISO now
    i_miso   : in  std_logic;                                   -- SPI master in / slave out
    o_data   : out std_logic_vector(G_DATA_WIDTH - 1 downto 0); -- last received word
    o_valid  : out std_logic                                    -- 1-cycle pulse: o_data updated
  );
end entity spi_master_rx;

architecture rtl of spi_master_rx is

  -- Shift register that assembles the incoming bits (MSB first).
  signal shift_reg : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
  -- Number of bits received in the current transfer.
  signal bit_cnt   : natural range 0 to G_DATA_WIDTH := 0;
  -- Output register and valid strobe.
  signal data_r    : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal valid_r   : std_logic := '0';

begin

  p_rx : process (i_clk)
    variable next_word : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  begin
    if rising_edge(i_clk) then
      valid_r <= '0';

      if i_rst = '1' then
        shift_reg <= (others => '0');
        bit_cnt   <= 0;
        data_r    <= (others => '0');
      elsif i_start = '1' then
        bit_cnt <= 0;
      elsif i_sample = '1' then
        next_word := shift_reg(G_DATA_WIDTH - 2 downto 0) & i_miso;
        shift_reg <= next_word;
        if bit_cnt = G_DATA_WIDTH - 1 then
          data_r  <= next_word;   -- whole word received
          valid_r <= '1';
          bit_cnt <= 0;
        else
          bit_cnt <= bit_cnt + 1;
        end if;
      end if;
    end if;
  end process p_rx;

  o_data  <= data_r;
  o_valid <= valid_r;

end architecture rtl;
