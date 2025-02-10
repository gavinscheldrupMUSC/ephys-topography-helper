function ephys_topography()
    % Initialization
    runCountFilePath = 'runCount.mat';
    [protocolCounter, reRecordCount, runCount, lastSavedDate] = initializeRunCount(runCountFilePath);

    % Verify folder existence and load images
    imageFolder = 'C:\"insert path to atlas images here"';
    imageFiles = dir(fullfile(imageFolder, '*.jpg'));

    % Sort image files by number in the filename
    [sortedFiles, currentImageIndex] = sortImageFiles(imageFiles);

    % Create and display figure
    fig = figure;
    set(fig, 'KeyPressFcn', @keyPressed);
    displayImage(currentImageIndex);

    % Wait for user interaction
    uiwait(fig);

    % KeyPress Function
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
                % Load the current value of unsuccessfulAttemptCount from runCount.mat
                data = load(runCountFilePath, 'unsuccessfulAttemptCount');
                unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;

                % Now pass unsuccessfulAttemptCount when calling selectImage
                [protocolCounter, reRecordCount, runCount, unsuccessfulAttemptCount] = selectImage(currentImageIndex, protocolCounter, reRecordCount, runCount, lastSavedDate, sortedFiles, imageFolder, runCountFilePath, unsuccessfulAttemptCount);
            otherwise
                disp('Invalid key pressed. Use Enter key to select, right arrow to go forward, or left arrow to go to previous.');
        end
    end


    % Display Image Function
    function displayImage(index)
        img = imread(fullfile(imageFolder, sortedFiles(index).name));
        imshow(img);
        title(['Image ', num2str(index), ' of ', num2str(length(sortedFiles)), ...
            '. Press Enter to select this image, right arrow to go to next, left arrow to go to previous.']);
    end
end

%% selectImage Function
function [protocolCounter, reRecordCount, runCount, unsuccessfulAttemptCount] = selectImage(index, protocolCounter, reRecordCount, runCount, lastSavedDate, sortedFiles, imageFolder, runCountFilePath, unsuccessfulAttemptCount)
baseSaveFolder = 'C:\"path to save folder"';

% Load the current unsuccessfulAttemptCount if it's not passed
if nargin < 8 || isempty(unsuccessfulAttemptCount)
    data = load(runCountFilePath, 'unsuccessfulAttemptCount');
    unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;
end

currentDate = datestr(now, 'mmddyyyy');
selectedImage = imread(fullfile(imageFolder, sortedFiles(index).name));
closeFigureIfExists(gcf); % Ensure no lingering figures
fig = figure;
imshow(selectedImage);
title('Click on the approximate location of the cell');
[xLocation, yLocation] = ginput(1);
selectedImage = overlayRedDot(selectedImage, xLocation, yLocation);
figure; imshow(selectedImage);
pause(2); close(gcf);

% Ask if the patch was successful
patchSuccess = questdlg('Patch successful?', 'Patch Confirmation', 'Yes', 'No', 'Yes');
if strcmp(patchSuccess, 'Yes')
    disp('Patch Successful!');
    % Increment runCount for a successful patch
    runCount = runCount + 1;

    % Ask if you want to proceed with recording or abort
    proceedOrAbort = questdlg('Do you want to proceed with recording?', ...
        'Proceed or Abort', 'Proceed', 'Abort', 'Proceed');

    if strcmp(proceedOrAbort, 'Abort')
        % Save to Unhealthy Cells with incremented runCount
        disp('Patch aborted. Saving data to Unhealthy Cells folder...');
        saveToUnhealthyCells(selectedImage, sortedFiles(index).name, runCount, baseSaveFolder, currentDate);

        % Save updated runCount and protocol state before exiting
        save(runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate');

        % Ensure figure is closed before exiting
        closeFigureIfExists(fig);
        return; % Exit the function early without recording logic
    end

    % Proceed with recording logic
    reRecord = true;
    while reRecord
        % Collect protocol data
        [baselineInputs, rampInputs, spikingInputs, finalMembraneInputs] = promptForDataAndSave(selectedImage, sortedFiles(index).name, index, baseSaveFolder, protocolCounter, reRecordCount, runCount);

        % Increment protocolCounter by 4 for each new recording session
        protocolCounter = protocolCounter + 4;

        % Ask if re-record is needed
        reRecord = handleReRecordPrompt();
        if reRecord
            reRecordCount = reRecordCount + 1;
        end
    end

    % Ask if the final recording was successful
    recordSuccess = questdlg('Recording successful?', 'Recording Confirmation', 'Yes', 'No', 'Yes');
    if strcmp(recordSuccess, 'Yes')
        disp('Recording successful! Saving data to base folder...');
        reRecordCount = 0; % Reset reRecordCount for the next cell

        % Save the image and protocols
        subfolderName = sprintf('Cell%d_%s_%s', runCount, sortedFiles(index).name(1:end-4), currentDate);
        subfolderPath = fullfile(baseSaveFolder, currentDate, subfolderName);
        imgWithText = applyTextOverlays(selectedImage, baselineInputs, rampInputs, spikingInputs, finalMembraneInputs, protocolCounter, runCount);
        saveImageToFolder(subfolderPath, sortedFiles(index).name, imgWithText, runCount, currentDate);
    else
        % Save to Unhealthy Cells for unsuccessful recording
        disp('Recording unsuccessful. Saving data to Unhealthy Cells folder...');

        % Define the Unhealthy Cells folder path
        unhealthyFolder = fullfile(baseSaveFolder, currentDate, 'Unhealthy Cells');
        if ~exist(unhealthyFolder, 'dir')
            mkdir(unhealthyFolder); % Create the folder if it doesn't exist
        end

        % Save the decoding file in the base folder first
        subfolderName = sprintf('Cell%d_%s_%s', runCount, sortedFiles(index).name(1:end-4), currentDate);
        subfolderPath = fullfile(baseSaveFolder, currentDate, subfolderName);
        decodingFileName = fullfile(subfolderPath, sprintf('%s_decoding.txt', subfolderName));

        % Ensure the decoding file exists before attempting to move it
        if exist(decodingFileName, 'file')
            % Move the decoding file to the Unhealthy Cells folder
            movefile(decodingFileName, unhealthyFolder);
        else
            warning('Decoding file not found: %s', decodingFileName);
        end

        % Save the image to Unhealthy Cells with Failed Recording designation
        saveToUnhealthyCells(selectedImage, sortedFiles(index).name, runCount, baseSaveFolder, currentDate, true, baselineInputs, rampInputs, spikingInputs, finalMembraneInputs, protocolCounter);

        % Check if the original subfolder is empty and delete if it is
        if exist(subfolderPath, 'dir')  % Ensure the subfolder exists
            folderContents = dir(subfolderPath);  % Get folder contents
            folderContents = folderContents(~ismember({folderContents.name}, {'.', '..'}));  % Remove '.' and '..'

            if isempty(folderContents)  % Check if the folder is empty
                rmdir(subfolderPath);  % Delete the empty subfolder
            else
                warning('The folder %s is not empty and cannot be deleted.', subfolderPath);
            end
        end
    end
else
    % Patch unsuccessful: Save as an unsuccessful attempt
    disp('Patch failed :(');
    unsuccessfulAttemptCount = saveUnsuccessfulPatch(selectedImage, sortedFiles(index).name, runCountFilePath);
end

% Save state to runCount.mat
save(runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount', 'lastSavedDate');
closeFigureIfExists(fig);
end

%% Helper Functions
function [protocolCounter, reRecordCount, runCount, lastSavedDate, unsuccessfulAttemptCount] = initializeRunCount(runCountFilePath)
    % Get the current date
    currentDate = datestr(now, 'mmddyyyy');
    
    % Check if the file exists
    if exist(runCountFilePath, 'file')
        % Load all variables in the file
        data = load(runCountFilePath);
        
        % Initialize missing variables
        if ~isfield(data, 'protocolCounter')
            protocolCounter = 0;
        else
            protocolCounter = data.protocolCounter;
        end
        
        if ~isfield(data, 'reRecordCount')
            reRecordCount = 0;
        else
            reRecordCount = data.reRecordCount;
        end
        
        if ~isfield(data, 'runCount')
            runCount = 0;
        else
            runCount = data.runCount;
        end
        
        if ~isfield(data, 'lastSavedDate')
            lastSavedDate = currentDate;  % Set to current date if missing
        else
            lastSavedDate = data.lastSavedDate;
        end
        
        if ~isfield(data, 'unsuccessfulAttemptCount')
            unsuccessfulAttemptCount = 0;  % Initialize to 0 if missing
        else
            unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;
        end
        
        % Reset counters if the saved date differs from the current date
        if ~strcmp(lastSavedDate, currentDate)
            protocolCounter = 0;
            reRecordCount = 0;
            runCount = 0;
            unsuccessfulAttemptCount = 0;  % Reset this as well
            lastSavedDate = currentDate;
        end
    else
        % Initialize all variables if the file doesn't exist
        protocolCounter = 0;
        reRecordCount = 0;
        runCount = 0;
        unsuccessfulAttemptCount = 0;
        lastSavedDate = currentDate;
    end
    
    % Save the current state back to the file
    save(runCountFilePath, 'runCount', 'protocolCounter', 'reRecordCount', 'lastSavedDate', 'unsuccessfulAttemptCount');
end

function value = getFieldOrDefault(data, fieldName, defaultValue)
    if isfield(data, fieldName)
        value = data.(fieldName);
    else
        value = defaultValue;
    end
end


function closeFigureIfExists(f)
    if isvalid(f)
        close(f);
    end
end

function selectedImage = overlayRedDot(image, x, y)
    markerSize = 80;
    lineWidth = 10;
    image = insertShape(image, 'FilledCircle', [x, y, markerSize / 2], 'Color', 'black', 'LineWidth', lineWidth);
    image = insertShape(image, 'FilledCircle', [x, y, markerSize / 2 - lineWidth / 2], 'Color', [255, 0, 0], 'LineWidth', lineWidth);
    selectedImage = image;
end

function saveImageToFolder(folderPath, imageName, image, runCount, currentDate)
    % Ensure the folder exists, if not, create it
    if ~exist(folderPath, 'dir')
        mkdir(folderPath);
    end

    % Construct the save name using the specified naming convention
    saveName = sprintf('Cell%d_%s_%s.jpg', runCount, imageName(1:end-4), currentDate);

    % Full path to the image file
    fullFileName = fullfile(folderPath, saveName);

    % Save the image
    imwrite(image, fullFileName);

    % Display a message confirming the saved image
    disp(['Saved successful recording image as ', saveName]);
end

function unsuccessfulAttemptCount = saveUnsuccessfulPatch(selectedImage, selectedImageName, runCountFilePath)
    baseSaveFolder = 'C:\"path to save folder"';
    currentDate = datestr(now, 'mmddyyyy');
    saveFolder = fullfile(baseSaveFolder, currentDate, 'Unsuccessful attempts');
    
    if ~exist(saveFolder, 'dir')
        mkdir(saveFolder);
    end
    
    % Load the current runCount and unsuccessfulAttemptCount
    data = load(runCountFilePath, 'unsuccessfulAttemptCount', 'runCount');
    
    % Increment the unsuccessful attempt count
    unsuccessfulAttemptCount = data.unsuccessfulAttemptCount + 1;
    
    % Save the incremented unsuccessful attempt count
    save(runCountFilePath, 'unsuccessfulAttemptCount', '-append');
    
    % Generate the save name with the updated unsuccessful attempt count
    saveName = sprintf('Attempt%d_%s_%s.jpg', unsuccessfulAttemptCount, selectedImageName(1:end - 4), currentDate);
    
    % Save the image with the updated name
    imwrite(selectedImage, fullfile(saveFolder, saveName));
    disp(['Saved unsuccessful patch image as ', saveName]);
end

function protocolStart = calculateProtocolStart(protocolCounter)
    % Calculate protocolStart based solely on protocolCounter
    protocolStart = protocolCounter + 1;  % Ensure it starts at 1 (not 0) for proper numbering
end

function inputs = createCustomDialogWithBaseline(dialogName, fields, baselineValues)
    % Debugging: Display baseline values in the command window
    disp('Baseline values passed to the dialog:');
    disp(baselineValues);

    % Create a dialog showing the baseline values alongside the input fields
    dialogWidth = 600;
    dialogHeight = 50 + length(fields) * 40;  % Adjust height based on the number of fields
    d = dialog('Position', [300, 300, dialogWidth, dialogHeight], 'Name', dialogName);
    fontSize = 10.5;

    % Display baseline values for the first 3 fields (Series Resistance, Membrane Capacitance, Membrane Resistance)
    for i = 1:length(fields)
        if i <= length(baselineValues)  % Only display baseline values for the first 3 fields
            % Ensure baseline value exists and is correctly formatted for display
            if isnan(baselineValues(i))
                baselineText = ' (Baseline: N/A)';
            else
                baselineText = [' (Baseline: ', num2str(baselineValues(i)), ')'];
            end
        else
            baselineText = '';  % No baseline for the 'Notes' field
        end
        % Debugging: Log which baseline is being assigned to which field
        disp(['Assigning baseline to field ', num2str(i), ': ', baselineText]);

        % Create the label with baseline information
        uicontrol('Parent', d, 'Style', 'text', 'Position', [20, dialogHeight - 40 * i, 250, 20], ...
            'String', [fields{i}, baselineText], 'FontSize', fontSize);
        
        % Create the input field
        inputFields{i} = uicontrol('Parent', d, 'Style', 'edit', 'Position', [280, dialogHeight - 40 * i, 100, 22], 'FontSize', fontSize);
    end

    % Submit button
    uicontrol('Parent', d, 'Style', 'pushbutton', 'Position', [400, 30, 100, 30], 'String', 'Submit', ...
        'FontSize', fontSize, 'Callback', @(~,~) uiresume(d));

    uiwait(d);  % Wait for user input

    % Capture the inputs
    inputs = cellfun(@(x) get(x, 'String'), inputFields, 'UniformOutput', false);
    delete(d);  % Close dialog after capturing inputs
end

function inputs = createCustomDialog(dialogName, fields)
    dialogWidth = 500;
    dialogHeight = 50 + length(fields) * 40;  % Adjust height based on the number of fields
    d = dialog('Position', [300, 300, dialogWidth, dialogHeight], 'Name', dialogName);
    fontSize = 10.5;

    % Create input fields dynamically based on the provided 'fields'
    inputFields = cell(1, length(fields));
    for i = 1:length(fields)
        uicontrol('Parent', d, 'Style', 'text', 'Position', [20, dialogHeight - 40*i, 200, 20], ...
            'String', fields{i}, 'FontSize', fontSize);
        inputFields{i} = uicontrol('Parent', d, 'Style', 'edit', 'Position', [250, dialogHeight - 40*i, 100, 22], 'FontSize', fontSize);
    end

    % Submit button
    uicontrol('Parent', d, 'Style', 'pushbutton', 'Position', [350, 30, 100, 30], 'String', 'Submit', ...
        'FontSize', fontSize, 'Callback', @(~,~) uiresume(d));

    uiwait(d);  % Wait for user input

    % Capture the inputs
    inputs = cellfun(@(x) get(x, 'String'), inputFields, 'UniformOutput', false);
    delete(d);  % Close dialog after capturing inputs
end

function reRecordNeeded = handleReRecordPrompt()
    reRecord = questdlg('Do you want to re-record?', 'Re-record', 'Yes', 'No', 'No');
    if strcmp(reRecord, 'Yes')
        reRecordNeeded = true;
    else
        reRecordNeeded = false;
    end
end

function saveToUnhealthyCells(image, imageName, runCount, baseSaveFolder, currentDate, addProtocol, baselineInputs, rampInputs, spikingInputs, finalMembraneInputs, protocolCounter)
    % Handle optional arguments
    if nargin < 6
        addProtocol = false; % Default: no protocol overlays
    end

    unhealthyFolder = fullfile(baseSaveFolder, currentDate, 'Unhealthy Cells');
    if ~exist(unhealthyFolder, 'dir')
        mkdir(unhealthyFolder); % Create the folder if it doesn't exist
    end

    % Generate file name
    if addProtocol
        saveName = sprintf('Cell%d_%s_%s_FailedRecording.jpg', runCount, imageName(1:end-4), currentDate);
        imgWithText = applyTextOverlays(image, baselineInputs, rampInputs, spikingInputs, finalMembraneInputs, protocolCounter, runCount);
    else
        saveName = sprintf('Cell%d_%s_%s_Aborted.jpg', runCount, imageName(1:end-4), currentDate);
        imgWithText = image; % Save without overlays
    end

    % Save the image
    imwrite(imgWithText, fullfile(unhealthyFolder, saveName));
    disp(['Saved unhealthy cell image as ', saveName]);
end

%% Write decoding file and print values

% Collect baseline, ramp, spiking, and final membrane properties
function [baselineInputs, rampInputs, spikingInputs, finalMembraneInputs] = promptForDataAndSave(selectedImage, selectedImageName, index, baseSaveFolder, protocolCounter, reRecordCount, runCount)

    % Prompt for baseline membrane properties first
    baselineInputs = createCustomDialog('Baseline Membrane Properties', {'Series Resistance (MΩ)', 'Membrane Capacitance (pF)', 'Membrane Resistance (MΩ)', 'Notes'});
    
    % Save baseline inputs
    baselineValues = str2double(baselineInputs(1:3)); % Assuming the first 3 fields are numeric
    
    % Continue with other data prompts
    rampInputs = createCustomDialog('Ramp Protocol', {'Ramp protocol held at (pA)', 'Ramp at natural RMP (mV)', 'Notes'});
    spikingInputs = createCustomDialog('Spiking Protocol', {'Spiking protocol held at (pA)', 'Spiking at natural RMP (mV)', 'Notes'});
    
    % Modify the final membrane input dialog to display baseline values
    finalMembraneInputs = createCustomDialogWithBaseline('Final Membrane Properties', {'Series Resistance (MΩ)', 'Membrane Capacitance (pF)', 'Membrane Resistance (MΩ)', 'Notes'}, baselineValues);

    % Compare final membrane properties with baseline values
    finalValues = str2double(finalMembraneInputs(1:3));
    percentChange = abs((finalValues - baselineValues) ./ baselineValues) * 100;
    
    % Check if any value has changed by more than 20%
    if any(percentChange > 20)
        warning('Some membrane properties have changed by more than 20%. Consider re-recording.');
    end

    % Ensure correct protocol numbers are saved based on protocolCounter and reRecordCount
    protocolStart = calculateProtocolStart(protocolCounter);  % Use protocolCounter and reRecordCount for the start

    % Write data to the decoding file
    currentDate = datestr(now, 'mmddyyyy');
    subfolderName = sprintf('Cell%d_%s_%s', runCount, selectedImageName(1:end-4), currentDate);
    subfolderPath = fullfile(baseSaveFolder, currentDate, subfolderName);

    % Ensure the folder exists before saving
    if ~exist(subfolderPath, 'dir')
        mkdir(subfolderPath);
    end

    decodingFileName = fullfile(subfolderPath, sprintf('%s_decoding.txt', subfolderName));

    % Open the file for appending
    fid = fopen(decodingFileName, 'a');
    if fid == -1
        error('Failed to open file: %s', decodingFileName);
    end

    % Write the protocol data
    if ftell(fid) > 0
        fprintf(fid, '\n---------------------------------------------\n');
    end

    fprintf(fid, '# Decoding File for Cell %d - Date: %s\n', runCount, currentDate);
    fprintf(fid, '---------------------------------------------\n');
    fprintf(fid, 'Current-clamped at -70mV:\n');
    fprintf(fid, 'File Name     Protocol Type     Current Injection (pA)\n');
    fprintf(fid, '---------------------------------------------\n');
    fprintf(fid, '%03d          Ramp (I-clamp)     %s pA\n', protocolStart, rampInputs{1});
    fprintf(fid, '%03d          Spiking (I-clamp)  %s pA\n', protocolStart + 2, spikingInputs{1});
    fprintf(fid, '\nNo Current Injection (RMP):\n');
    fprintf(fid, 'File Name     Protocol Type     RMP (mV)\n');
    fprintf(fid, '---------------------------------------------\n');
    fprintf(fid, '%03d          Ramp (RMP)         %s mV\n', protocolStart + 1, rampInputs{2});
    fprintf(fid, '%03d          Spiking (RMP)      %s mV\n', protocolStart + 3, spikingInputs{2});

    % Baseline and final membrane properties
    writeMembraneProperties(fid, 'Baseline Membrane Properties', baselineInputs);
    writeMembraneProperties(fid, 'Final Membrane Properties', finalMembraneInputs);
    
    % Close the file
    fclose(fid);
end

function imgWithText = applyTextOverlays(image, baselineInputs, rampInputs, spikingInputs, finalMembraneInputs, protocolCounter, runCount)
% Construct the text for baseline membrane properties
baselineText = sprintf('Baseline: SR: %s MΩ, MC: %s pF, MR: %s MΩ\nFinal: SR: %s MΩ, MC: %s pF, MR: %s MΩ', ...
    baselineInputs{1}, baselineInputs{2}, baselineInputs{3}, ...
    finalMembraneInputs{1}, finalMembraneInputs{2}, finalMembraneInputs{3});

% Construct the text for ramp and spiking protocols using protocolStart
rampSpikingText = sprintf('Ramp: %03d: I-clamp @ %s pA, %03d: RMP @ %s mV\nSpiking: %03d: I-clamp @ %s pA, %03d: RMP @ %s mV', ...
    protocolCounter - 3, rampInputs{1}, protocolCounter - 2, rampInputs{2}, protocolCounter - 1, spikingInputs{1}, protocolCounter, spikingInputs{2});

% Construct the title for the cell
cellTitle = sprintf('Cell %d, %s', runCount, datestr(now, 'mmddyyyy'));

% Add text overlays to the image
imgWithText = insertText(image, [20, size(image, 1) - 200], baselineText, 'FontSize', 125, 'BoxOpacity', 0.4, 'AnchorPoint', 'LeftBottom');
imgWithText = insertText(imgWithText, [size(image, 2) - 20, size(image, 1) - 200], rampSpikingText, 'FontSize', 125, 'BoxOpacity', 0.4, 'AnchorPoint', 'RightBottom');
imgWithText = insertText(imgWithText, [size(image, 2) / 2, 100], cellTitle, 'FontSize', 200, 'BoxOpacity', 0, 'AnchorPoint', 'CenterTop');
end


function writeMembraneProperties(fid, sectionTitle, inputs)
fprintf(fid, '%s:\n', sectionTitle);
fprintf(fid, 'Series Resistance: %s MΩ\n', inputs{1});
fprintf(fid, 'Membrane Capacitance: %s pF\n', inputs{2});
fprintf(fid, 'Membrane Resistance: %s MΩ\n', inputs{3});
fprintf(fid, 'Notes: %s\n\n', inputs{4});
end

% Added missing sortImageFiles function
function [sortedFiles, currentIndex] = sortImageFiles(files)
    fileNames = {files.name};
    numbers = cellfun(@(x) sscanf(x, '%fmm.jpg'), fileNames, 'UniformOutput', false);
    numbersMat = cell2mat(numbers);
    [~, sortedIdx] = sort(numbersMat, 'ascend');
    sortedFiles = files(sortedIdx);
    currentIndex = 1;

end
