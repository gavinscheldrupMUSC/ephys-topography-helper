=======================================
MATLAB EPHYS TOPOGRAPHY & LOGGING SCRIPT
=======================================


OVERVIEW
--------
This is a MATLAB script package that provides a GUI to streamline the process of whole-cell patch-clamp electrophysiology recordings.

Its primary purpose is to integrate anatomical targeting (selecting a cell's location from a brain atlas) with systematic data logging, quality control, and automated file organization.

The script guides the user through selecting a location, then prompts for experimental parameters (e.g., Series Resistance, RMP) and protocol notes at key stages of the recording. It automatically tracks protocol numbers, generates a decoding file for each cell, and saves a summary image of the cell's location with key data overlaid.

It also includes robust logic for handling patch failure and cell death during recording.


FEATURES
--------
* Visual Atlas Navigation: Use arrow keys to navigate through a series of brain atlas images.
* Click-to-Mark: Click on the selected atlas image to mark the precise location of your cell.

* Automated File Structure: Automatically creates a daily, animal-specific folder structure (e.g., `10202025_Mouse1M_CIE-FSS`) to store all data.

* Cell-by-Cell Logging: Saves data for each successfully patched cell (`runCount`) in a unique subfolder (e.g., `Cell1_1.200mm_10202025`).

* Decoding File: Generates a `_decoding.txt` file for each cell that maps experimental protocols (Ramp, Spiking, sEPSC) to their corresponding protocol numbers and logs all entered membrane properties and notes.

* Summary Image: Saves a copy of the atlas image with a red dot marking the cell's location and an overlay of key data (protocol numbers, membrane properties, animal info).

* Live Quality Control (QC): Actively prompts for membrane properties at baseline, post-excitability, and final stages. It automatically flags significant drift (>20%) and asks the user how to proceed.

* Re-record & Abort Logic:
    * If a QC check fails, the user can "Re-record" that set of protocols. The script logs the failed attempt in the decoding file and advances the protocol counter.
    * The user can "Abort" an unhealthy cell at any stage, which moves all associated data to an "Unhealthy Cells" subfolder for later review.

* Failure Logging: Failed patch attempts are logged separately in an "Unsuccessful attempts" folder.


DEPENDENCIES
------------
* MATLAB
* Image Processing Toolbox (Required for `imshow`, `ginput`, `insertShape`, `insertText`).


SETUP & INSTALLATION
--------------------
The setup is semi-automatic. You do NOT need to manually edit any files with your folder paths.

1.  SAVE THE SCRIPT FILES:
    Save all three of these .m files into the same folder, or somewhere on your MATLAB path:
    * `ephys_topography.m` (The main script)
    * `setupConfig.m` (The setup/configuration helper)
    * `setRunCount.m` (The manual counter utility)

2.  RUN THE SCRIPT FOR THE FIRST TIME:
    In the MATLAB command window, type:
    >> ephys_topography

3.  FIRST-TIME SETUP (Interactive):
    * The script will detect that this is the first run.
    * A pop-up window will appear: "Select the folder containing your Atlas images". Navigate to and select your atlas folder.
    * A second pop-up will appear: "Select the base folder for saving Ephys data". Navigate to and select the main folder where you want your daily data saved (e.g., `C:\MyLab\EphysData`).

4.  SETUP COMPLETE:
    * The script saves your choices into a file named `ephys_config.mat`.
    * It will not ask you for these folders again.
    * If you ever move or delete these folders, the script will detect the broken path and automatically re-prompt you to select new ones.


!! CRITICAL: ATLAS IMAGE NAMING !!
----------------------------------
This script will fail if your atlas images are not named correctly. The script sorts your atlas slices based on the *number* in the filename.

The filename MUST be named with a numerical coordinate indicating distance from bregma followed by "mm".

    GOOD EXAMPLES:
    1.700mm.jpg
    1.580mm.jpg
    -0.500mm.png
    1.2mm.tif

    BAD EXAMPLES (Will not work):
    Atlas_1.7.jpg
    Coronal_Slice_1.jpg
    PFC_1.700.jpg


HOW TO USE (NORMAL WORKFLOW)
----------------------------
1.  Run the script by typing `ephys_topography` in the MATLAB command window.

2.  Enter Animal Info (Once per day):
    * A dialog box will ask for the "Animal name", "Animal sex (M/F)", and "Animal Condition".
    * This creates the main folder for the day (e.g., `10202025_Mouse1M_CIE-FSS`).

3.  Select Atlas Location:
    * An atlas image is displayed. Use the LEFT and RIGHT ARROW KEYS to navigate through the slices.
    * Press ENTER to select the current atlas slice.

4.  Mark Cell Location:
    * The selected image opens in a new window. CLICK on the approximate location of your cell. A red dot will be overlaid.

5.  Patch Success?:
    * A dialog asks "Patch successful?".
    * NO: The script logs the image to the "Unsuccessful attempts" folder and waits for you to start again.
    * YES: The `runCount` (e.g., "Cell 1") is incremented.

6.  Proceed or Abort?:
    * A prompt asks "Do you want to proceed with recording?".
    * ABORT: If the cell is unhealthy *before* recording, click "Abort". The patch is saved to the "Unhealthy Cells" folder.
    * PROCEED: The main recording workflow begins.

7.  Enter Protocol Data:
    * You will be prompted by a series of dialog boxes to enter membrane properties and notes for:
        1.  Baseline Membrane Properties
        2.  Ramp Protocol
        3.  Spiking Protocol

8.  First QC Check (Post-excitability):
    * You are prompted to enter the "Post-excitability Membrane Properties".
    * The script compares these to the baseline. If a >20% change is detected, a warning appears.
    * You can choose:
        * 'Continue Anyway': Accepts the drift and proceeds.
        * 'Re-record': Logs the first set of protocols as "failed" in the decoding file, advances the protocol counter, and prompts you to re-enter data (steps 7 & 8).
        * 'Abort': Moves all data for this cell to "Unhealthy Cells".

9.  sEPSC and Final QC Check:
    * You are prompted for "sEPSC Recordings" and "Final Membrane Properties".
    * This triggers a second QC check with the same "Continue", "Re-record", or "Abort" logic.

10. Final Save:
    * If all steps are completed, the script generates the final `_decoding.txt` file and summary `.jpg` image in the cell's folder.
    * A final prompt asks, "Recording successful?".
    * YES: The cell folder is saved, and the script is ready for the next cell.
    * NO: (e.g., the cell died during the final sEPSC recording). The *entire* populated cell folder is moved to "Unhealthy Cells" for review.


TROUBLESHOOTING & UTILITIES (setRunCount.m)
-----------------------------------------
`setRunCount.m` is a utility script you run manually from the command window if you need to fix a counter or reset your animal. You DO NOT run this during normal recording.

COMMON USES:
1.  You deleted "Cell 5" and want the next cell to be "Cell 5" again.
2.  The script crashed, and the counters are wrong.
3.  You are starting a new animal on the *same day*.

HOW TO USE (Examples):
Type these commands into the MATLAB Command Window.

    >> setRunCount(4)
    * This manually sets the 'runCount' to 4.
    * The *next* cell you record will be "Cell 5".
    * It leaves all other counters (protocol, unsuccessful) as they are.

    >> setRunCount(4, 8)
    * This sets the 'runCount' to 4 (so next cell is 5) AND sets the
        'unsuccessfulAttemptCount' to 8.

    >> setRunCount(0)
    * This is the "BIG RESET" button.
    * It resets ALL counters to 0 (runCount, protocolCounter, reRecordCount, unsuccessfulAttemptCount).
    * It will also pop up a dialog box asking you to enter NEW animal info.
    	***This is the command to use when you finish one animal and start a new animal on the same day.***


OUTPUT FILE STRUCTURE
---------------------
This is how your data folder will be organized:

[Your Base Save Folder]/
│
└── 20251020_Mouse1M_CIE-FSS/
    │
    ├── Cell1_1.700mm_20251020/
    │   ├── Cell1_1.700mm_20251020.jpg           (Summary image)
    │   └── Cell1_1.700mm_20251020_decoding.txt  (Decoding file)
    │
    ├── Cell2_1.580mm_20251020/
    │   ├── Cell2_1.580mm_20251020.jpg
    │   └── Cell2_1.580mm_20251020_decoding.txt
    │
    ├── Unhealthy Cells/
    │   ├── Cell3_1.580mm_20251020_Aborted/      (Cell aborted after QC check)
    │   │   ├── Cell3_1.580mm_20251020.jpg
    │   │   └── Cell3_1.580mm_20251020_decoding.txt
    │   └── Cell4_1.700mm_20251020_Aborted.jpg   (Cell aborted immediately after patching)
    │
    └── Unsuccessful attempts/
        ├── Attempt1_1.700mm_20251020.jpg       (Failed patch attempt 1)
        └── Attempt2_1.580mm_20251020.jpg       (Failed patch attempt 2)