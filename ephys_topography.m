function ephys_topography()
    % --- Setup Configuration ---
    config = setupConfig();
    % Initialization using the config file path
    [protocolCounter, reRecordCount, runCount, lastSavedDate, unsuccessfulAttemptCount, animalName, animalSex, animalCond] = initializeRunCount(config);
    % Verify folder existence and load images using config
    imageFiles = dir(fullfile(config.imageFolder, config.atlasExtension)); 
    if isempty(imageFiles)
        error('No atlas image files found in the specified folder: %s. Check the path and file extension in config.', config.imageFolder);
    end
    % Sort image files by number in the filename
    [sortedFiles, currentImageIndex] = sortImageFiles(imageFiles);
    
    if isempty(sortedFiles)
        error('Could not sort any atlas files. Ensure filenames match the expected pattern (e.g., "1.234mm.jpg" or "-0.500mm.jpg").');
    end
    % Create and display figure
    fig = figure;
    set(fig, 'KeyPressFcn', @keyPressed);
    displayImage(currentImageIndex);
    % Wait for user interaction
    uiwait(fig);
    % --- Nested Functions ---
    function keyPressed(~, event)
        switch event.Key
            case 'rightarrow'
                if currentImageIndex < length(sortedFiles)
                    currentImageIndex = currentImageIndex + 1;
                    displayImage(currentImageIndex);
                end
            case 'leftarrow'
                if currentImageIndex > 1
                    currentImageIndex = currentImageIndex - 1;
                    displayImage(currentImageIndex);
                end
            case {'return', 'enter'}
                data = load(config.runCountFilePath, 'unsuccessfulAttemptCount');
                unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;
                % Pass the entire 'config' structure to selectImage
                [protocolCounter, reRecordCount, runCount, unsuccessfulAttemptCount] = ...
                    selectImage(currentImageIndex, protocolCounter, reRecordCount, runCount, lastSavedDate, ...
                                sortedFiles, unsuccessfulAttemptCount, animalName, animalSex, animalCond, config); % Pass config
            otherwise
                disp('Invalid key pressed. Use Enter key to select, right arrow to go forward, or left arrow to go to previous.');
        end
    end
    function displayImage(index)
        % Use config for image folder path
        img = imread(fullfile(config.imageFolder, sortedFiles(index).name));
        imshow(img);
        titleStr = sprintf('Image %d of %d. Press Enter to select, arrows to navigate.', ...
                           index, length(sortedFiles));
        title(titleStr);
        
        [~, coordinate, ~] = fileparts(sortedFiles(index).name);
        
        text(0.5, 0.95, coordinate, 'Units', 'normalized', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
             'Color', 'white', 'FontSize', 16, 'FontWeight', 'bold', ...
             'BackgroundColor', 'black', 'Margin', 2);
    end
end
%% selectImage Function
function [protocolCounter, reRecordCount, runCount, unsuccessfulAttemptCount] = selectImage(index, protocolCounter, reRecordCount, runCount, lastSavedDate, sortedFiles, unsuccessfulAttemptCount, animalName, animalSex, animalCond, config)
    if nargin < 9 || isempty(unsuccessfulAttemptCount)
        data = load(config.runCountFilePath, 'unsuccessfulAttemptCount');
        unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;
    end
    currentDate = datestr(now, 'mmddyyyy');
    % --- NEW: Create the new base folder name ---
    baseDateFolder = sprintf('%s_%s%s_%s', currentDate, animalName, animalSex, animalCond);

    selectedImage = imread(fullfile(config.imageFolder, sortedFiles(index).name)); 
    
    [~, selectedImageNameStem, ~] = fileparts(sortedFiles(index).name);
    closeFigureIfExists(gcf);
    fig = figure;
    imshow(selectedImage);
    title('Click on the approximate location of the cell');
    [xLocation, yLocation] = ginput(1);
    selectedImage = overlayRedDot(selectedImage, xLocation, yLocation);
    figure; imshow(selectedImage);
    pause(2); close(gcf);
    patchSuccess = questdlg('Patch successful?', 'Patch Confirmation', 'Yes', 'No', 'Yes');
    if strcmp(patchSuccess, 'Yes')
        disp('Patch Successful!');
        runCount = runCount + 1;
        
        proceedOrAbort = questdlg('Do you want to proceed with recording?', 'Proceed or Abort', 'Proceed', 'Abort', 'Proceed');
        if strcmp(proceedOrAbort, 'Abort')
            disp('Patch aborted. Saving image to Unhealthy Cells folder...');
            % --- MODIFIED: Pass the new baseDateFolder ---
            saveToUnhealthyCells(selectedImage, selectedImageNameStem, runCount, config.baseSaveFolder, baseDateFolder); 
            save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond'); 
            closeFigureIfExists(fig);
            return;
        end
        
        % Initialize variables to store successful data and logs of failed attempts
        baselineInputs = {}; rampInputs = {}; spikingInputs = {}; 
        sEPSCInputs = {}; postExcitabilityInputs = {}; finalMembraneInputs = {};
        failedExcitabilityLogs = {};
        failed_sEPSC_Logs = {};
        keepOuterLooping = true;
        while keepOuterLooping
            baseCounterForAttempt = protocolCounter;
            sEPSCProtocolOffset = 0;
            % --- Initial Data and Post-excitability Check ---
            [currentBaseline, currentRamp, currentSpiking, baselineValues] = promptForInitialAndRampSpiking();
            [currentPostExcitability, choice] = promptAndCheckProperties(baselineValues, 'Post-excitability Membrane Properties');
            
            if strcmp(choice, 'Re-record')
                disp('Storing failed excitability attempt and re-recording...');
                reRecordCount = reRecordCount + 1;
                logEntry.baseCounter = baseCounterForAttempt;
                logEntry.baselineInputs = currentBaseline;
                logEntry.rampInputs = currentRamp;
                logEntry.spikingInputs = currentSpiking;
                logEntry.membraneInputs = currentPostExcitability;
                failedExcitabilityLogs{end+1} = logEntry;
                
                protocolCounter = protocolCounter + 4;
                save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond');
                continue; 
            elseif strcmp(choice, 'Abort')
                disp('Aborting cell recording...');
                subfolderName = sprintf('Cell%d_%s_%s_Aborted_PostExcitability', runCount, selectedImageNameStem, currentDate);
                % --- MODIFIED: Use new baseDateFolder ---
                abortedFolderPath = fullfile(config.baseSaveFolder, baseDateFolder, subfolderName);
                if ~exist(abortedFolderPath, 'dir'); mkdir(abortedFolderPath); end
                
                decodingFileName = fullfile(abortedFolderPath, sprintf('%s_decoding.txt', subfolderName));
                writeFinalDecodingFile(decodingFileName, true, runCount, animalName, animalSex, animalCond, currentDate, baseCounterForAttempt, 0, currentBaseline, currentRamp, currentSpiking, {}, currentPostExcitability, {}, {}, {});
                imgWithText = applyTextOverlays(selectedImage, baseCounterForAttempt, 0, currentBaseline, currentRamp, currentSpiking, {}, currentPostExcitability, {}, runCount, animalName, animalSex, animalCond);
                saveImageToFolder(abortedFolderPath, selectedImageNameStem, imgWithText, runCount, currentDate, 'Aborted_PostExcitability');
                % --- MODIFIED: Use new baseDateFolder ---
                unhealthyParentPath = fullfile(config.baseSaveFolder, baseDateFolder, 'Unhealthy Cells');
                if ~exist(unhealthyParentPath, 'dir'); mkdir(unhealthyParentPath); end
                movefile(abortedFolderPath, unhealthyParentPath);
                protocolCounter = protocolCounter + 4;
                save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond');
                closeFigureIfExists(fig);
                return;
            end
            
            baselineInputs = currentBaseline;
            rampInputs = currentRamp;
            spikingInputs = currentSpiking;
            postExcitabilityInputs = currentPostExcitability;
            % --- sEPSC and Final Membrane Check ---
            keepInnerLooping = true;
            while keepInnerLooping
                [current_sEPSCInputs] = createCustomDialog('sEPSC Recordings', {'sEPSCs at -70mV (Notes)', 'sEPSCs at -55mV (Notes)'});
                [currentFinalMembrane, finalChoice] = promptAndCheckProperties(baselineValues, 'Final Membrane Properties');
                switch finalChoice
                    case 'Re-record'
                        disp('Storing failed sEPSC attempt and re-recording...');
                        reRecordCount = reRecordCount + 1;
                        logEntry_sEPSC.baseCounter = protocolCounter;
                        logEntry_sEPSC.membraneInputs = currentFinalMembrane;
                        failed_sEPSC_Logs{end+1} = logEntry_sEPSC;
                        sEPSCProtocolOffset = sEPSCProtocolOffset + 2;
                        protocolCounter = protocolCounter + 2;
                        save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond');
                        continue; 
                    case 'Abort'
                        disp('Aborting cell after final check...');
                        
                        % --- CORRECTED FINAL ABORT LOGIC ---
                        % 1. Create a descriptive folder for the aborted data
                        subfolderName = sprintf('Cell%d_%s_%s_Aborted_FinalCheck', runCount, selectedImageNameStem, currentDate);
                        % --- MODIFIED: Use new baseDateFolder ---
                        abortedFolderPath = fullfile(config.baseSaveFolder, baseDateFolder, subfolderName);
                        if ~exist(abortedFolderPath, 'dir'); mkdir(abortedFolderPath); end
                        % 2. Write all available data to the decoding file
                        decodingFileName = fullfile(abortedFolderPath, sprintf('%s_decoding.txt', subfolderName));
                        sEPSCInputs = current_sEPSCInputs;
                        finalMembraneInputs = currentFinalMembrane;
                        writeFinalDecodingFile(decodingFileName, true, runCount, animalName, animalSex, animalCond, currentDate, baseCounterForAttempt, sEPSCProtocolOffset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, failedExcitabilityLogs, failed_sEPSC_Logs);
                        
                        % 3. Generate and save the corresponding image
                        imgWithText = applyTextOverlays(selectedImage, baseCounterForAttempt, sEPSCProtocolOffset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, runCount, animalName, animalSex, animalCond);
                        saveImageToFolder(abortedFolderPath, selectedImageNameStem, imgWithText, runCount, currentDate, 'Aborted_FinalCheck');
                        
                        % 4. Move the complete folder to Unhealthy Cells
                        % --- MODIFIED: Use new baseDateFolder ---
                        unhealthyParentPath = fullfile(config.baseSaveFolder, baseDateFolder, 'Unhealthy Cells');
                        if ~exist(unhealthyParentPath, 'dir'); mkdir(unhealthyParentPath); end
                        movefile(abortedFolderPath, unhealthyParentPath);
                        
                        % 5. Update counter and exit
                        protocolCounter = baseCounterForAttempt + 6 + sEPSCProtocolOffset;
                        save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond');
                        closeFigureIfExists(fig);
                        return;
                    case 'Continue'
                        sEPSCInputs = current_sEPSCInputs;
                        finalMembraneInputs = currentFinalMembrane;
                        keepInnerLooping = false;
                end
            end
            
            protocolCounter = baseCounterForAttempt + 6 + sEPSCProtocolOffset;
            keepOuterLooping = false; 
        end
        
        % --- Final Write and Save ---
        subfolderName = sprintf('Cell%d_%s_%s', runCount, selectedImageNameStem, currentDate);
        % --- MODIFIED: Use new baseDateFolder ---
        initialSubfolderPath = fullfile(config.baseSaveFolder, baseDateFolder, subfolderName);
        if ~exist(initialSubfolderPath, 'dir'); mkdir(initialSubfolderPath); end
        decodingFileName = fullfile(initialSubfolderPath, sprintf('%s_decoding.txt', subfolderName));
        
        writeFinalDecodingFile(decodingFileName, false, runCount, animalName, animalSex, animalCond, currentDate, baseCounterForAttempt, sEPSCProtocolOffset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, failedExcitabilityLogs, failed_sEPSC_Logs);
        
        recordSuccess = questdlg('Recording successful?', 'Recording Confirmation', 'Yes', 'No', 'Yes');
        
        imgWithText = applyTextOverlays(selectedImage, baseCounterForAttempt, sEPSCProtocolOffset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, runCount, animalName, animalSex, animalCond);
        if strcmp(recordSuccess, 'Yes')
            disp('Recording successful! Saving data to base folder...');
            reRecordCount = 0; 
            saveImageToFolder(initialSubfolderPath, selectedImageNameStem, imgWithText, runCount, currentDate);
        else
            disp('Recording unsuccessful. Moving data to Unhealthy Cells folder...');
            % --- MODIFIED: Use new baseDateFolder ---
            unhealthyParentPath = fullfile(config.baseSaveFolder, baseDateFolder, 'Unhealthy Cells');
            if ~exist(unhealthyParentPath, 'dir'); mkdir(unhealthyParentPath); end
            movefile(initialSubfolderPath, unhealthyParentPath);
            finalUnhealthyCellPath = fullfile(unhealthyParentPath, subfolderName);
            saveImageToFolder(finalUnhealthyCellPath, selectedImageNameStem, imgWithText, runCount, currentDate, 'FailedRecording');
        end
    else
        disp('Patch failed :(');
        % --- MODIFIED: Pass animal info to create correct folder name ---
        unsuccessfulAttemptCount = saveUnsuccessfulPatch(selectedImage, selectedImageNameStem, config.runCountFilePath, config.baseSaveFolder, animalName, animalSex, animalCond);
    end
    
    save(config.runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate', 'animalName', 'animalSex', 'animalCond');
    closeFigureIfExists(fig);
end
%% Helper Functions
%% Helper Functions
function [protocolCounter, reRecordCount, runCount, lastSavedDate, unsuccessfulAttemptCount, animalName, animalSex, animalCond] = initializeRunCount(config)
    currentDate = datestr(now, 'mmddyyyy');
    runCountFilePath = config.runCountFilePath; % Get path from config

    % Define conditions list
    conditions = {"Baseline", "AIR-NS", "AIR-FSS", "CIE-NS", "CIE-FSS"};

    if exist(runCountFilePath, 'file')
        data = load(runCountFilePath);
        % Load all data, providing defaults if fields are missing
        protocolCounter = getFieldOrDefault(data, 'protocolCounter', 0);
        reRecordCount = getFieldOrDefault(data, 'reRecordCount', 0);
        runCount = getFieldOrDefault(data, 'runCount', 0);
        lastSavedDate = getFieldOrDefault(data, 'lastSavedDate', currentDate);
        unsuccessfulAttemptCount = getFieldOrDefault(data, 'unsuccessfulAttemptCount', 0);
        animalName = getFieldOrDefault(data, 'animalName', '');
        animalSex  = getFieldOrDefault(data, 'animalSex', '');
        animalCond = getFieldOrDefault(data, 'animalCond', '');
        
        % Construct the expected folder path based on saved info
        baseDateFolder = sprintf('%s_%s%s_%s', currentDate, animalName, animalSex, animalCond);
        expectedFolderPath = fullfile(config.baseSaveFolder, baseDateFolder);

        % --- NEW LOGIC ---
        % Re-prompt if it's a new day OR if the user deleted the base folder for today
        if ~strcmp(lastSavedDate, currentDate) || (isfield(data, 'animalName') && ~exist(expectedFolderPath, 'dir'))
            if ~strcmp(lastSavedDate, currentDate)
                % If it's a new day, reset all daily counters
                protocolCounter = 0;
                reRecordCount = 0;
                runCount = 0;
                unsuccessfulAttemptCount = 0;
                lastSavedDate = currentDate;
                disp('New day detected. Resetting daily counters and prompting for animal info.');
            else
                % If only the folder was deleted, just re-prompt for info
                disp('Base folder not found. Prompting for new animal information.');
            end
            
            % Prompt for new info in either case
            [animalName, animalSex, animalCond] = promptForNewAnimalInfo(conditions);
        end
        
    else
        % If the runCount file doesn't exist at all, initialize everything
        protocolCounter = 0;
        reRecordCount = 0;
        runCount = 0;
        unsuccessfulAttemptCount = 0;
        lastSavedDate = currentDate;
        [animalName, animalSex, animalCond] = promptForNewAnimalInfo(conditions);
    end
    
    save(runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'lastSavedDate', 'unsuccessfulAttemptCount', 'animalName', 'animalSex', 'animalCond');
end

function [name, sex, cond] = promptForNewAnimalInfo(conditions)
    % This helper function encapsulates the dialogs for entering animal info
    prompt = {'Enter animal name:', 'Enter animal sex (use M/F):'};
    dlg_title = 'Enter Daily Animal Info';
    answer = inputdlg(prompt, dlg_title, 1, {'',''});
    
    if ~isempty(answer)
        name = answer{1};
        sex  = answer{2};
        
        [indx, tf] = listdlg('ListString', conditions, 'SelectionMode', 'single', 'Name', 'Select Animal Condition', 'PromptString', 'Select the animal condition:');
        if tf
            cond = conditions{indx};
        else
            cond = '';
            disp('Animal condition selection cancelled. Value set to empty.');
        end
    else
        name = '';
        sex = '';
        cond = '';
        disp('Animal info input cancelled. Values set to empty.');
    end
end

function value = getFieldOrDefault(data, fieldName, defaultValue)
    if isfield(data, fieldName)
        value = data.(fieldName);
    else
        value = defaultValue;
    end
end
function closeFigureIfExists(f)
    if exist('f', 'var') && isvalid(f)
        close(f);
    end
end
function selectedImage = overlayRedDot(image, x, y)
    markerSize = 80;
    lineWidth = 10;
    image = insertShape(image, 'FilledCircle', [x, y, markerSize / 2], 'Color', 'black', 'Opacity', 1);
    image = insertShape(image, 'FilledCircle', [x, y, markerSize / 2 - lineWidth], 'Color', [255, 0, 0], 'Opacity', 1);
    selectedImage = image;
end
function saveImageToFolder(folderPath, imageNameStem, image, runCount, currentDate, nameSuffix)
    if nargin < 6
        nameSuffix = ''; % Default to no suffix
    end
    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end
    
    if isempty(nameSuffix)
        saveName = sprintf('Cell%d_%s_%s.jpg', runCount, imageNameStem, currentDate);
    else
        saveName = sprintf('Cell%d_%s_%s_%s.jpg', runCount, imageNameStem, currentDate, nameSuffix);
    end
    fullFileName = fullfile(folderPath, saveName);
    imwrite(image, fullFileName);
    if isempty(nameSuffix)
        disp(['Saved successful recording image as ', saveName]);
    else
        disp(['Saved unhealthy recording data to folder: ', folderPath]);
    end
end
% --- MODIFIED: Function signature updated to accept animal info ---
function unsuccessfulAttemptCount = saveUnsuccessfulPatch(selectedImage, imageNameStem, runCountFilePath, baseSaveFolder, animalName, animalSex, animalCond)
    currentDate = datestr(now, 'mmddyyyy');
    % --- NEW: Create the new base folder name ---
    baseDateFolder = sprintf('%s_%s%s_%s', currentDate, animalName, animalSex, animalCond);
    % --- MODIFIED: Use the new baseDateFolder for the path ---
    saveFolder = fullfile(baseSaveFolder, baseDateFolder, 'Unsuccessful attempts');
    
    if ~exist(saveFolder, 'dir')
        mkdir(saveFolder);
    end
    
    if exist(runCountFilePath, 'file')
        data = load(runCountFilePath, 'unsuccessfulAttemptCount');
        currentUnsuccessfulCount = getFieldOrDefault(data, 'unsuccessfulAttemptCount', 0);
    else
        currentUnsuccessfulCount = 0;
    end
    
    unsuccessfulAttemptCount = currentUnsuccessfulCount + 1;
    
    if exist(runCountFilePath, 'file')
        allData = load(runCountFilePath);
        allData.unsuccessfulAttemptCount = unsuccessfulAttemptCount;
        save(runCountFilePath, '-struct', 'allData');
    else
        save(runCountFilePath, 'unsuccessfulAttemptCount');
    end
    saveName = sprintf('Attempt%d_%s_%s.jpg', unsuccessfulAttemptCount, imageNameStem, currentDate);
    imwrite(selectedImage, fullfile(saveFolder, saveName));
    disp(['Saved unsuccessful patch image as ', saveName]);
end
function protocolStart = calculateProtocolStart(protocolCounter)
    protocolStart = protocolCounter + 1;
end
function inputs = createCustomDialogWithBaseline(dialogName, fields, baselineValues)
    disp('Baseline values passed to the dialog:');
    disp(baselineValues);
    dialogWidth = 600;
    dialogHeight = 50 + length(fields) * 40;
    d = dialog('Position', [300, 300, dialogWidth, dialogHeight], 'Name', dialogName);
    fontSize = 10.5;
    inputFields = cell(1, length(fields));
    for i = 1:length(fields)
        baselineText = '';
        if i <= length(baselineValues) && ~isempty(baselineValues)
            if isnan(baselineValues(i))
                baselineText = ' (Baseline: N/A)';
            else
                baselineText = [' (Baseline: ', num2str(baselineValues(i)), ')'];
            end
        end
        uicontrol('Parent', d, 'Style', 'text', 'Position', [20, dialogHeight - 40*i, 250, 20], ...
            'String', [fields{i}, baselineText], 'FontSize', fontSize, 'HorizontalAlignment', 'left');
        inputFields{i} = uicontrol('Parent', d, 'Style', 'edit', 'Position', [280, dialogHeight - 40*i, 100, 22], 'FontSize', fontSize);
    end
    uicontrol('Parent', d, 'Style', 'pushbutton', 'Position', [dialogWidth/2 - 50, 10, 100, 30], 'String', 'Submit', ...
        'FontSize', fontSize, 'Callback', @(~,~) uiresume(d));
    uiwait(d);
    if isvalid(d)
        inputs = cellfun(@(x) get(x, 'String'), inputFields, 'UniformOutput', false);
        delete(d);
    else
        inputs = cell(1, length(fields));
        inputs(:) = {''};
        disp('Dialog was closed before submitting.');
    end
end
function inputs = createCustomDialog(dialogName, fields)
    dialogWidth = 500;
    dialogHeight = 50 + length(fields) * 40;
    d = dialog('Position', [300, 300, dialogWidth, dialogHeight], 'Name', dialogName);
    fontSize = 10.5;
    inputFields = cell(1, length(fields));
    for i = 1:length(fields)
        uicontrol('Parent', d, 'Style', 'text', 'Position', [20, dialogHeight - 40*i, 200, 20], ...
            'String', fields{i}, 'FontSize', fontSize, 'HorizontalAlignment', 'left');
        inputFields{i} = uicontrol('Parent', d, 'Style', 'edit', 'Position', [250, dialogHeight - 40*i, 100, 22], 'FontSize', fontSize);
    end
    uicontrol('Parent', d, 'Style', 'pushbutton', 'Position', [dialogWidth/2 - 50, 10, 100, 30], 'String', 'Submit', ...
        'FontSize', fontSize, 'Callback', @(~,~) uiresume(d));
    uiwait(d);
    if isvalid(d)
        inputs = cellfun(@(x) get(x, 'String'), inputFields, 'UniformOutput', false);
        delete(d);
    else
        inputs = cell(1, length(fields));
        inputs(:) = {''};
        disp('Dialog was closed before submitting.');
    end
end
function reRecordNeeded = handleReRecordPrompt()
    reRecord = questdlg('Do you want to re-record?', 'Re-record', 'Yes', 'No', 'No');
    if strcmp(reRecord, 'Yes')
        reRecordNeeded = true;
    else
        reRecordNeeded = false;
    end
end
% --- MODIFIED: Function signature updated to use baseDateFolder ---
function saveToUnhealthyCells(image, imageNameStem, runCount, baseSaveFolder, baseDateFolder)
    % --- MODIFIED: Path constructed with baseDateFolder ---
    unhealthyFolder = fullfile(baseSaveFolder, baseDateFolder, 'Unhealthy Cells');
    
    if ~exist(unhealthyFolder, 'dir')
        mkdir(unhealthyFolder);
    end
    
    currentDate = datestr(now, 'mmddyyyy');
    saveName = sprintf('Cell%d_%s_%s_Aborted.jpg', runCount, imageNameStem, currentDate);
    
    imwrite(image, fullfile(unhealthyFolder, saveName));
    disp(['Saved aborted patch image as ', saveName]);
end
function [baselineInputs, rampInputs, spikingInputs, baselineValues] = promptForInitialAndRampSpiking()
    baselineInputs = createCustomDialog('Baseline Membrane Properties', {'Series Resistance (MΩ)', 'Membrane Resistance (MΩ)', 'Membrane Capacitance (pF)', 'Notes'});
    baselineValues = [];
    if ~all(cellfun('isempty', baselineInputs(1:3)))
        baselineValues = str2double(baselineInputs(1:3));
        if any(isnan(baselineValues))
             warning('Non-numeric input for baseline properties. Calculations might be affected.');
             baselineValues = [];
        end
    else
        disp('Baseline inputs are empty. Skipping baseline values for dialogs.');
    end
    
    rampInputs = createCustomDialog('Ramp Protocol', {'Ramp protocol held at (pA)', 'Ramp at natural RMP (mV)', 'Notes'});
    spikingInputs = createCustomDialog('Spiking Protocol', {'Spiking protocol held at (pA)', 'Spiking at natural RMP (mV)', 'Notes'});
end
function [inputs, choice] = promptAndCheckProperties(baselineValues, dialogTitle)
    choice = 'Continue'; 
    
    if ~isempty(baselineValues)
        inputs = createCustomDialogWithBaseline(dialogTitle, ...
            {'Series Resistance (MΩ)', 'Membrane Resistance (MΩ)', 'Membrane Capacitance (pF)', 'Notes'}, baselineValues);
    else
        inputs = createCustomDialog([dialogTitle, ' (No Baseline Ref)'], ...
            {'Series Resistance (MΩ)', 'Membrane Resistance (MΩ)', 'Membrane Capacitance (pF)', 'Notes'});
    end
    
    if ~all(cellfun('isempty', inputs(1:3))) && ~isempty(baselineValues) && ~any(isnan(baselineValues))
        finalValues = str2double(inputs(1:3));
        if ~any(isnan(finalValues))
            percentChange = abs((finalValues - baselineValues) ./ baselineValues) * 100;
            if any(percentChange > 20)
                user_choice = questdlg(sprintf('One or more properties changed by >20%%.\n\nSR Change: %.1f%%\nMR Change: %.1f%%\nMC Change: %.1f%%\n\nWhat would you like to do?', ...
                    percentChange(1), percentChange(2), percentChange(3)), ...
                    'Significant Change Detected', 'Continue Anyway', 'Re-record', 'Abort', 'Continue Anyway');
                
                switch user_choice
                    case 'Re-record'
                        choice = 'Re-record';
                    case 'Abort'
                        choice = 'Abort';
                    case 'Continue Anyway'
                        choice = 'Continue';
                    case '' 
                        choice = 'Abort';
                end
            end
        else
            warning('Non-numeric input for properties. Skipping percent change calculation.');
        end
    end
end
function writeFinalDecodingFile(decodingFileName, isAborted, runCount, animalName, animalSex, animalCond, currentDate, baseCounter, sEPSC_Offset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, failedExcitabilityLogs, failed_sEPSC_Logs)
    fid = fopen(decodingFileName, 'w');
    if fid == -1
        error('Failed to open file for writing: %s', decodingFileName);
    end
    if ~isempty(failedExcitabilityLogs) || ~isempty(failed_sEPSC_Logs)
        fprintf(fid, 'NOTE: This cell was re-recorded due to membrane property drift. See FAILED ATTEMPT logs below for details.\n\n');
    end
    fprintf(fid, '========================================================\n');
    fprintf(fid, '--- FINAL SUCCESSFUL RECORDING DATA ---\n');
    fprintf(fid, '========================================================\n');
    % --- BUG FIX: Corrected format string to include animalCond ---
    fprintf(fid, '# Decoding File for Cell %d - %s%s (%s) - Date: %s\n', runCount, animalName, animalSex, animalCond, currentDate);
    fprintf(fid, '---------------------------------------------\n');
    
    excitabilityStart = calculateProtocolStart(baseCounter);
    sEPSC_Start = calculateProtocolStart(baseCounter + 4 + sEPSC_Offset);
    fprintf(fid, 'Current-clamped at -70mV:\n');
    fprintf(fid, 'File Name     Protocol Type     Current Injection (pA)\n');
    fprintf(fid, '---------------------------------------------\n');
    fprintf(fid, '%03d          Ramp (I-clamp)     %s pA\n', excitabilityStart, rampInputs{1});
    fprintf(fid, '%03d          Spiking (I-clamp)  %s pA\n', excitabilityStart + 2, spikingInputs{1});
    fprintf(fid, '\nNo Current Injection (RMP):\n');
    fprintf(fid, 'File Name     Protocol Type     RMP (mV)\n');
    fprintf(fid, '---------------------------------------------\n');
    fprintf(fid, '%03d          Ramp (RMP)         %s mV\n', excitabilityStart + 1, rampInputs{2});
    fprintf(fid, '%03d          Spiking (RMP)      %s mV\n', excitabilityStart + 3, spikingInputs{2});
    
    if ~isempty(sEPSCInputs)
        fprintf(fid, '\nVoltage-clamped:\n');
        fprintf(fid, 'File Name     Protocol Type         Holding Potential (mV)\n');
        fprintf(fid, '--------------------------------------------------------\n');
        fprintf(fid, '%03d          sEPSC                 -70 mV\n', sEPSC_Start);
        fprintf(fid, '%03d          sEPSC                 -55 mV\n', sEPSC_Start + 1);
    end
    
    writeMembraneProperties(fid, 'Baseline Membrane Properties', baselineInputs);
    writeMembraneProperties(fid, 'Post-excitability Membrane Properties', postExcitabilityInputs);
    if ~isempty(finalMembraneInputs)
        writeMembraneProperties(fid, 'Final Membrane Properties', finalMembraneInputs);
    end
    
    fprintf(fid, '\n--- Protocol-Specific Notes ---\n');
    fprintf(fid, 'Ramp Notes: %s\n', rampInputs{3});
    fprintf(fid, 'Spiking Notes: %s\n', spikingInputs{3});
    if ~isempty(sEPSCInputs)
        fprintf(fid, 'sEPSC @ -70mV Notes: %s\n', sEPSCInputs{1});
        fprintf(fid, 'sEPSC @ -55mV Notes: %s\n', sEPSCInputs{2});
    end
    
    if isAborted
        fprintf(fid, '\n*** FINAL RECORDING ATTEMPT WAS ABORTED. ***\n');
    end
    for i = 1:length(failedExcitabilityLogs)
        log = failedExcitabilityLogs{i};
        protocolStart = calculateProtocolStart(log.baseCounter);
        fprintf(fid, '\n\n--------------------------------------------------------');
        fprintf(fid, '\n--- FAILED EXCITABILITY ATTEMPT (Protocols %03d-%03d) ---', protocolStart, protocolStart + 3);
        fprintf(fid, '\n--- Reason: Unhealthy -- re-recorded ---\n');
        writeMembraneProperties(fid, 'Baseline At Failure', log.baselineInputs);
        writeMembraneProperties(fid, 'Post-excitability At Failure', log.membraneInputs);
        fprintf(fid, '\nRamp Notes: %s\n', log.rampInputs{3});
        fprintf(fid, 'Spiking Notes: %s\n', log.spikingInputs{3});
        fprintf(fid, '\n--------------------------------------------------------');
    end
    for i = 1:length(failed_sEPSC_Logs)
        log = failed_sEPSC_Logs{i};
        protocolStart = calculateProtocolStart(log.baseCounter);
        fprintf(fid, '\n\n--------------------------------------------------------');
        fprintf(fid, '\n--- FAILED sEPSC ATTEMPT (Protocols %03d-%03d) ---', protocolStart + 4, protocolStart + 5);
        fprintf(fid, '\n--- Reason: Unhealthy -- re-recorded ---\n');
        writeMembraneProperties(fid, 'Final Properties At Failure', log.membraneInputs);
        fprintf(fid, '\n--------------------------------------------------------');
    end
    fclose(fid);
end
function imgWithText = applyTextOverlays(image, baseCounter, sEPSC_Offset, baselineInputs, rampInputs, spikingInputs, sEPSCInputs, postExcitabilityInputs, finalMembraneInputs, runCount, animalName, animalSex, animalCond)
    if isempty(postExcitabilityInputs); postExcitabilityInputs = {'','','',''}; end
    if isempty(finalMembraneInputs); finalMembraneInputs = {'','','',''}; end
    membraneText = sprintf('Baseline: SR: %s MΩ, MR: %s MΩ, MC: %s pF\nPost-Excitability: SR: %s MΩ, MR: %s MΩ, MC: %s pF\nFinal: SR: %s MΩ, MR: %s MΩ, MC: %s pF', ...
        baselineInputs{1}, baselineInputs{2}, baselineInputs{3}, ...
        postExcitabilityInputs{1}, postExcitabilityInputs{2}, postExcitabilityInputs{3}, ...
        finalMembraneInputs{1}, finalMembraneInputs{2}, finalMembraneInputs{3});
    
    excitabilityStart = baseCounter + 1;
    sEPSC_Start = baseCounter + 5 + sEPSC_Offset;
    rampSpikingText = sprintf('Ramp: %03d: I-clamp @ %s pA, %03d: RMP @ %s mV\nSpiking: %03d: I-clamp @ %s pA, %03d: RMP @ %s mV', ...
        excitabilityStart, rampInputs{1}, excitabilityStart + 1, rampInputs{2}, ...
        excitabilityStart + 2, spikingInputs{1}, excitabilityStart + 3, spikingInputs{2});
    if isempty(sEPSCInputs)
        sEPSCText = 'sEPSC: (Aborted)';
    else
        sEPSCText = sprintf('sEPSC: %03d @ -70mV, %03d @ -55mV', ...
            sEPSC_Start, sEPSC_Start + 1);
    end
    
    % --- BUG FIX: Corrected format string to include animalCond ---
    animalInfoText = sprintf('%s%s (%s)', animalName, animalSex, animalCond); 
    cellTitle = sprintf('Cell %d, %s, %s', runCount, animalInfoText, datestr(now, 'mmddyyyy'));
    
    imgWithText = insertText(image, [20, size(image, 1)-250], membraneText, 'FontSize', 125, 'BoxOpacity', 0.4, 'AnchorPoint', 'LeftBottom');
    imgWithText = insertText(imgWithText, [size(image, 2)-20, size(image, 1)-300], rampSpikingText, 'FontSize', 125, 'BoxOpacity', 0.4, 'AnchorPoint', 'RightBottom');
    imgWithText = insertText(imgWithText, [size(image, 2)-30, size(image, 1)-160], sEPSCText, 'FontSize', 125, 'BoxOpacity', 0.4, 'AnchorPoint', 'RightBottom');
    imgWithText = insertText(imgWithText, [size(image, 2)/2, 100], cellTitle, 'FontSize', 200, 'BoxOpacity', 0, 'AnchorPoint', 'CenterTop');
end
function writeMembraneProperties(fid, sectionTitle, inputs)
    fprintf(fid, '\n%s:\n', sectionTitle);
    fprintf(fid, 'Series Resistance: %s MΩ\n', inputs{1});
    fprintf(fid, 'Membrane Resistance: %s MΩ\n', inputs{2});
    fprintf(fid, 'Membrane Capacitance: %s pF\n', inputs{3});
    fprintf(fid, 'Notes: %s\n', inputs{4});
end
function [sortedFiles, currentIndex] = sortImageFiles(files)
    fileNames = {files.name};
    numbers = cellfun(@(x) sscanf(x, '%fmm'), fileNames, 'UniformOutput', false);
    
    validParse = ~cellfun('isempty', numbers);
    
    if ~any(validParse)
        error('No atlas files matched the expected naming pattern (e.g., "NUMBERmm.ext") for sorting. Please check the atlas folder and filenames.');
    end
    
    if ~all(validParse)
        nonMatchingFiles = fileNames(~validParse);
        warning('Some atlas filenames did not match the expected pattern and were ignored for sorting:\n%s', strjoin(nonMatchingFiles, '\n'));
        files = files(validParse);
        numbers = numbers(validParse);
    end
    
    numbersMat = cell2mat(numbers);
    [~, sortedIdx] = sort(numbersMat, 'descend');
    sortedFiles = files(sortedIdx);
    currentIndex = 1;
    if isempty(sortedFiles)
        error('Sorting resulted in an empty list of files. Please check atlas filenames.');
    end
end