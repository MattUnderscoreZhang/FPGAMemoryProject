module BlockMemoryStorage(
    clock,
    clearMemory,
    readMemory,
    newAddress,
    storageReady,
    SSID,
    hitInfo,
    readReady
    );

`include "MyParameters.vh"

// inputs and outputs
input clock, clearMemory, readMemory, newAddress;
output reg storageReady, readReady;
input [SSIDBITS-1:0] SSID;
input [HITINFOBITS-1:0] hitInfo;

// SSID splitting
reg [ROWINDEXBITS_HNM-1:0] rowIndex = 0;
reg [COLINDEXBITS_HNM-1:0] colIndex = 0, HCMColIndex = 0;

// block memory inputs and outputs
wire enable = 1;
reg writeEnableA_HNM, writeEnableB_HNM, writeEnableA_HCM, writeEnableB_HCM, writeEnableA_HIM, writeEnableB_HIM;
reg [ROWINDEXBITS_HNM-1:0] rowIndexA_HNM, rowIndexB_HNM;
reg [ROWINDEXBITS_HCM-1:0] rowIndexA_HCM, rowIndexB_HCM;
reg [ROWINDEXBITS_HIM-1:0] rowIndexA_HIM, rowIndexB_HIM;
reg [NCOLS_HNM-1:0] dataInputA_HNM, dataInputB_HNM;
reg [NCOLS_HCM-1:0] dataInputA_HCM, dataInputB_HCM;
reg [NCOLS_HIM-1:0] dataInputA_HIM, dataInputB_HIM;
wire [NCOLS_HNM-1:0] dataOutputA_HNM, dataOutputB_HNM;
wire [NCOLS_HCM-1:0] dataOutputA_HCM, dataOutputB_HCM;
wire [NCOLS_HIM-1:0] dataOutputA_HIM, dataOutputB_HIM;

// queues used for reading and writing
reg [NCOLS_HNM-1:0] queueNewHitsRow1_HNM, queueNewHitsRow2_HNM, queueNewHitsRow3_HNM;
reg [ROWINDEXBITS_HNM-1:0] queueRowIndex1_HNM, queueRowIndex2_HNM, queueRowIndex3_HNM;
reg [ROWINDEXBITS_HIM-1:0] queueAddress1_HCM, queueAddress2_HCM, queueAddress3_HCM;
reg [MAXHITNBITS-1:0] queueNewHitsN1_HCM, queueNewHitsN2_HCM, queueNewHitsN3_HCM;
reg [NCOLS_HIM-1:0] queueHitInfo1_HIM, queueHitInfo2_HIM, queueHitInfo3_HIM;
reg HNMInQueue1, HNMInQueue2, HNMInQueue3, HCMInQueue1, HCMInQueue2, HCMInQueue3, SSIDAlreadyHit;

// variables for tracking reading, writing, and clearing memory
integer clearingIndex, readingIndex;
reg [ROWINDEXBITS_HIM-1:0] nextAvailableHIMAddress;

initial begin
    storageReady = 1;
    readReady = 1;
    clearingIndex = -1;
    readingIndex = -1;
    writeEnableA_HNM = 0;
    writeEnableB_HNM = 0;
    writeEnableA_HCM = 0;
    writeEnableB_HCM = 0;
    writeEnableA_HIM = 0;
    writeEnableB_HIM = 0;
    HNMInQueue1 = 0;
    HNMInQueue2 = 0;
    HNMInQueue3 = 0;
    HCMInQueue1 = 0;
    HCMInQueue2 = 0;
    HCMInQueue3 = 0;
    nextAvailableHIMAddress = 0;
end

always @(posedge clock) begin

    // split SSID
    rowIndex[ROWINDEXBITS_HNM-1:0] = SSID[SSIDBITS-1:COLINDEXBITS_HNM];
    colIndex[COLINDEXBITS_HNM-1:0] = SSID[COLINDEXBITS_HNM-1:0];

    // reset everything
    writeEnableA_HNM = 0;
    writeEnableB_HNM = 0;
    writeEnableA_HCM = 0;
    writeEnableB_HCM = 0;
    writeEnableA_HIM = 0;
    writeEnableB_HIM = 0;
    storageReady = 1;
    readReady = 1;

    // clear the HNM if clearMemory goes high - don't read or write during this time
    if (clearMemory || clearingIndex >= 0) begin
        storageReady = 0;
        readReady = 0;
        if (clearingIndex < 0) clearingIndex = -1;
        clearingIndex = clearingIndex + 1;
        rowIndexA_HNM = clearingIndex;
        dataInputA_HNM = 0;
        writeEnableA_HNM = 1;
        if (clearingIndex < NROWS_HNM-1) begin
            clearingIndex = clearingIndex + 1;
            rowIndexB_HNM = clearingIndex;
            dataInputB_HNM = 0;
            writeEnableB_HNM = 1;
        end
        if (clearingIndex >= NROWS_HNM-1) begin
            nextAvailableHIMAddress = 0;
            clearingIndex = -1;
        end
    end

    // store new SSID - read from B, write from A
    // if there's a new SSID or something that still needs to be written
    if (storageReady && (newAddress || HNMInQueue1 || HNMInQueue2 || HNMInQueue3 || HCMInQueue1 || HCMInQueue2 || HCMInQueue3)) begin

        storageReady = 0;

        // if there's a new SSID, move it into the queue
        if (newAddress) begin

            /////////////////////////////////////////////
            // HNM - whether the hits at SSIDs are new //
            /////////////////////////////////////////////

            rowIndexB_HNM = rowIndex;
            queueRowIndex3_HNM = rowIndex;
            // if it's in a repeat row, merge
            if (rowIndex == queueRowIndex1_HNM && HNMInQueue1) begin
                queueNewHitsRow1_HNM = queueNewHitsRow1_HNM | 1'b1<<colIndex;
            end
            else if (rowIndex == queueRowIndex2_HNM && HNMInQueue2) begin
                queueNewHitsRow2_HNM = queueNewHitsRow2_HNM | 1'b1<<colIndex;
            end
            // if SSID is in new row, add to end of queue
            else begin
                queueNewHitsRow3_HNM = 1'b1<<colIndex;
                HNMInQueue3 = 1;
            end

            ////////////////////////////////////////////////////////////////////////////////////////
            // HCM - how many hits are at each SSID, and the HIM address where the info is stored //
            // HIM - hit info                                                                     //
            ////////////////////////////////////////////////////////////////////////////////////////

            rowIndexB_HCM = SSID;
            queueAddress3_HCM = SSID;
            // if it's a repeat SSID, merge
            if (SSID == queueAddress1_HCM && HCMInQueue1) begin
                queueNewHitsN1_HCM = queueNewHitsN1_HCM + 1;
                queueHitInfo1_HIM = queueHitInfo1_HIM<<HITINFOBITS | hitInfo;
            end
            else if (SSID == queueAddress2_HCM && HCMInQueue2) begin
                queueNewHitsN2_HCM = queueNewHitsN2_HCM + 1;
                queueHitInfo2_HIM = queueHitInfo2_HIM<<HITINFOBITS | hitInfo;
            end
            // if SSID is new, add to end of queue
            else begin
                queueNewHitsN3_HCM = 1;
                HCMInQueue3 = 1;
                queueHitInfo3_HIM = hitInfo;
            end
        end

        /////////////////////////////////////////////
        // HNM - whether the hits at SSIDs are new //
        /////////////////////////////////////////////

        // write queue1 if it exists
        if (HNMInQueue1) begin
            rowIndexA_HNM = queueRowIndex1_HNM;
            dataInputA_HNM = dataOutputB_HNM | queueNewHitsRow1_HNM;
            writeEnableA_HNM = 1;
            HNMInQueue1 = 0;
        end
        // move queue up
        if (HNMInQueue2) begin
            queueRowIndex1_HNM = queueRowIndex2_HNM;
            queueNewHitsRow1_HNM = queueNewHitsRow2_HNM;
            HNMInQueue1 = 1;
            HNMInQueue2 = 0;
        end
        if (HNMInQueue3) begin
            queueRowIndex2_HNM = queueRowIndex3_HNM;
            queueNewHitsRow2_HNM = queueNewHitsRow3_HNM;
            HNMInQueue2 = 1;
            HNMInQueue3 = 0;
        end

        ////////////////////////////////////////////////////////////////////////////////////////
        // HCM - how many hits are at each SSID, and the HIM address where the info is stored //
        // HIM - hit info                                                                     //
        ////////////////////////////////////////////////////////////////////////////////////////

        // if SSID hasn't been hit, use nextAvailableHIMAddress - else use existing address
        HCMColIndex[COLINDEXBITS_HNM-1:0] = queueAddress1_HCM[COLINDEXBITS_HNM-1:0];
        SSIDAlreadyHit = dataOutputB_HNM[HCMColIndex];

        // write queue1 if it exists
        if (HCMInQueue1) begin
            rowIndexA_HCM = queueAddress1_HCM;
            if (!SSIDAlreadyHit) begin
                dataInputA_HCM = queueNewHitsN1_HCM;
                dataInputA_HCM[NCOLS_HCM-1:NCOLS_HCM-ROWINDEXBITS_HIM] = nextAvailableHIMAddress[ROWINDEXBITS_HIM-1:0];
                rowIndexA_HIM = nextAvailableHIMAddress;
                nextAvailableHIMAddress = nextAvailableHIMAddress + 1;
                dataInputA_HIM = queueHitInfo1_HIM;
            end
            else begin
                dataInputA_HCM = dataOutputB_HCM + queueNewHitsN1_HCM; // assuming no overflow in number of hits
                rowIndexA_HIM = dataOutputB_HCM[NCOLS_HCM-1:NCOLS_HCM-ROWINDEXBITS_HIM];
                // right now the hit info gets overwritten if there's more than three hits in a row, or if hits are non-consecutive.
                // for an SSID, after reading the HCM to get the HIM address, we could then read the HIM, but that takes too long.
                //dataInputA_HIM = dataOutputB_HIM<<(HITINFOBITS * queueNewHitsN1_HCM) | queueHitInfo1_HIM;
                dataInputA_HIM = queueHitInfo1_HIM;
            end
            $display("Hits %h", queueNewHitsN1_HCM);
            $display("SSID %h", queueAddress1_HCM);
            $display("HIM %h %h", rowIndexA_HIM, queueHitInfo1_HIM);
            writeEnableA_HCM = 1;
            writeEnableA_HIM = 1;
            HCMInQueue1 = 0;
        end
        // move queue up
        if (HCMInQueue2) begin
            queueAddress1_HCM = queueAddress2_HCM;
            queueNewHitsN1_HCM = queueNewHitsN2_HCM;
            queueHitInfo1_HIM = queueHitInfo2_HIM;
            HCMInQueue1 = 1;
            HCMInQueue2 = 0;
        end
        if (HCMInQueue3) begin
            queueAddress2_HCM = queueAddress3_HCM;
            queueNewHitsN2_HCM = queueNewHitsN3_HCM;
            queueHitInfo2_HIM = queueHitInfo3_HIM;
            HCMInQueue2 = 1;
            HCMInQueue3 = 0;
        end

        storageReady = 1;
    end

    // read out the HCM if readMemory goes high - don't read or write during this time
    // if (readMemory || readingIndex >= 0) begin
    if (!newAddress && (readReady || readingIndex>=0)) begin
        storageReady = 0;
        readReady = 0;
        if (readingIndex < 0) readingIndex = -1;
        readingIndex = readingIndex + 1;
        rowIndexB_HCM = readingIndex;
        if (readingIndex >= NROWS_HCM-1) begin
            readingIndex = -1;
            storageReady = 1;
            readReady = 1;
        end
    end
end

blk_mem_gen_0 HitsNewMemory (
    .clka(clock),
    .ena(enable),
    .wea(writeEnableA_HNM),
    .addra(rowIndexA_HNM),
    .dina(dataInputA_HNM),
    .douta(dataOutputA_HNM),
    .clkb(clock),
    .enb(enable),
    .web(writeEnableB_HNM),
    .addrb(rowIndexB_HNM),
    .dinb(dataInputB_HNM),
    .doutb(dataOutputB_HNM)
    );

blk_mem_gen_1 HitsCountMemory (
    .clka(clock),
    .ena(enable),
    .wea(writeEnableA_HCM),
    .addra(rowIndexA_HCM),
    .dina(dataInputA_HCM),
    .douta(dataOutputA_HCM),
    .clkb(clock),
    .enb(enable),
    .web(writeEnableB_HCM),
    .addrb(rowIndexB_HCM),
    .dinb(dataInputB_HCM),
    .doutb(dataOutputB_HCM)
    );

blk_mem_gen_2 HitsListMemory (
    .clka(clock),
    .ena(enable),
    .wea(writeEnableA_HIM),
    .addra(rowIndexA_HIM),
    .dina(dataInputA_HIM),
    .douta(dataOutputA_HIM),
    .clkb(clock),
    .enb(enable),
    .web(writeEnableB_HIM),
    .addrb(rowIndexB_HIM),
    .dinb(dataInputB_HIM),
    .doutb(dataOutputB_HIM)
    );

endmodule
