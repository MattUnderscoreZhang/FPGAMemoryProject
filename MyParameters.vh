localparam NROWS_HNM = 16; //128;
localparam NCOLS_HNM = 16; //512;
localparam ROWINDEXBITS_HNM = $clog2(NROWS_HNM); // 7
localparam COLINDEXBITS_HNM = $clog2(NCOLS_HNM); // 9

localparam MAXHITN = 4; // max of 4 hits per SSID
localparam MAXHITNBITS = $clog2(MAXHITN); // 2

localparam NROWS_HLM = 8192; // can store this many hits per event (4 hits per SSID)
localparam ROWINDEXBITS_HLM = $clog2(NROWS_HLM); // 13
localparam NCOLS_HLM = 32; // information stored about hit

localparam NROWS_HCM = NROWS_HNM * NCOLS_HNM;
localparam ROWINDEXBITS_HCM = $clog2(NROWS_HCM); // 16
localparam ADDRESSBITS = ROWINDEXBITS_HCM;
localparam NCOLS_HCM = ROWINDEXBITS_HLM + MAXHITNBITS; // info for number of hits, plus address where first hit is stored
