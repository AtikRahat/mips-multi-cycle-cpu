	component cpu_issp_dmem3 is
		port (
			source : out std_logic_vector(0 downto 0);                      -- source
			probe  : in  std_logic_vector(191 downto 0) := (others => 'X')  -- probe
		);
	end component cpu_issp_dmem3;

	u0 : component cpu_issp_dmem3
		port map (
			source => CONNECTED_TO_source, -- sources.source
			probe  => CONNECTED_TO_probe   --  probes.probe
		);

