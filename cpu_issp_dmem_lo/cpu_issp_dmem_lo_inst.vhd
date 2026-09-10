	component cpu_issp_dmem_lo is
		port (
			probe  : in  std_logic_vector(479 downto 0) := (others => 'X'); -- probe
			source : out std_logic_vector(0 downto 0)                       -- source
		);
	end component cpu_issp_dmem_lo;

	u0 : component cpu_issp_dmem_lo
		port map (
			probe  => CONNECTED_TO_probe,  --  probes.probe
			source => CONNECTED_TO_source  -- sources.source
		);

