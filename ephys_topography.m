% Define the main function
function ephys_topography()
    % Load or initialize the run count and last saved date from a file
    runCountFilePath = 'runCount.mat';

    if exist(runCountFilePath, 'file')
        load(runCountFilePath, 'runCount', 'lastSavedDate');
    else
        runCount = 1;
        lastSavedDate = datestr(now, 'mmddyyyy'); % Initialize with current date
        save(runCountFilePath, 'runCount', 'lastSavedDate'); % Save initial state
    end

    % Define the path to the folder containing the images
    imageFolder = 'C:\Users\gavin\OneDrive\Ephys data\PFC Atlas RAW'; % Define your image folder path here
    imageFiles = dir(fullfile(imageFolder, '*.jpg')); % Adjust the file extension if needed

    if isempty(imageFiles)
        error('No JPG files found in the specified folder.');
    end

    % Extract the first number from filenames and sort them
    fileNames = {imageFiles.name};
    numbers = cellfun(@(x) sscanf(x, 'PFC_Fig%d_%fmm.jpg'), fileNames, 'UniformOutput', false);
    numbers = cellfun(@(x) x(1), numbers); % Extract only the first number
    [~, sortedIdx] = sort(numbers);
    sortedFiles = imageFiles(sortedIdx);

    % Initialize index for image navigation
    currentImageIndex = 1;

    % Create a figure to display images
    fig = figure;
    set(fig, 'KeyPressFcn', @keyPressed); % Set callback for key press

    % Display initial image
    displayImage(currentImageIndex);

    % Wait for user interaction
    uiwait(fig);

    % Callback function for key press
    function keyPressed(~, event)
        key = event.Key;
        switch key
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
            case {'return', 'enter'} % Use 'return' or 'enter' key to select image
                selectImage(currentImageIndex);
            otherwise
                disp('Invalid key pressed. Please use Enter key to select, right arrow to go forward, or left arrow to go back.');
        end
    end

    % Function to display image
    function displayImage(index)
        img = imread(fullfile(imageFolder, sortedFiles(index).name));
        imshow(img);
        title(['Image ', num2str(index), ' of ', num2str(length(sortedFiles)), ...
            '. Press Enter to select this image, right arrow to go to next, left arrow to go to previous.']);
    end

    % Function to select image
    function selectImage(index)
        selectedImage = imread(fullfile(imageFolder, sortedFiles(index).name));
        selectedImageName = sortedFiles(index).name;

        % Close the figure after selection
        close(fig);

        % Display the selected image and prompt user to click on the location for the red dot
        figure;
        imshow(selectedImage);
        title('Click on the location where you want to place the red dot');
        [xLocation, yLocation] = ginput(1);

        % Add a red dot to the selected image
        markerSize = 20; % Size of the marker
        lineWidth = 4;   % Thickness of the marker
        selectedImage = insertShape(selectedImage, 'FilledCircle', [xLocation, yLocation, markerSize/2], ...
            'Color', 'red', 'LineWidth', lineWidth);

        % Display the edited image with the red dot
        figure;
        imshow(selectedImage);
        title('Edited Image with Red Dot');

        % Automatically close edited image after 2 seconds
        pause(2);
        close(gcf);

        % Define the base path to save the edited image
        baseSaveFolder = 'C:\Users\gavin\OneDrive\Ephys data'; % Define your base save folder path here

        % Generate the current date folder name (mmddyyyy format)
        currentDate = datestr(now, 'mmddyyyy');
        
        % Create the folder if it doesn't exist
        saveFolder = fullfile(baseSaveFolder, currentDate);
        if ~exist(saveFolder, 'dir')
            mkdir(saveFolder);
        end

        % Confirmation window for patch success
        choice = questdlg('Patch successful?', 'Confirmation', 'Yes', 'No', 'Yes');

        if strcmp(choice, 'Yes')
            % Generate the save name with the current run count
            saveName = sprintf('Cell%d_%s', runCount, selectedImageName);
            imwrite(selectedImage, fullfile(saveFolder, saveName)); % Save in the current date folder

            disp(['Edited image saved as ', fullfile(saveFolder, saveName)]);

            % Increment the run count for the next run
            runCount = runCount + 1;
        else
            % Create a subfolder for unsuccessful attempts
            unsuccessfulFolder = fullfile(saveFolder, 'Unsuccessful attempts');
            if ~exist(unsuccessfulFolder, 'dir')
                mkdir(unsuccessfulFolder);
            end

            % Count the number of attempt files in the unsuccessful folder
            attemptFiles = dir(fullfile(unsuccessfulFolder, 'Attempt*.jpg'));
            attemptCount = length(attemptFiles) + 1;

            % Generate the save name for the attempt
            saveName = sprintf('Attempt%d_%s', attemptCount, selectedImageName);
            imwrite(selectedImage, fullfile(unsuccessfulFolder, saveName)); % Save in the unsuccessful folder

            disp(['Edited image saved as ', fullfile(unsuccessfulFolder, saveName)]);
        end

        % Save the updated run count and last saved date to the file
        lastSavedDate = currentDate; % Update last saved date
        save(runCountFilePath, 'runCount', 'lastSavedDate');

        % Close all figures at the end
        close all;
    end

end

% Function to manually set the run count
function setRunCount(newCount)
    runCountFilePath = 'runCount.mat';
    if exist(runCountFilePath, 'file')
        load(runCountFilePath, 'lastSavedDate');
    else
        lastSavedDate = datestr(now, 'mmddyyyy'); % Initialize with current date if file doesn't exist
    end
    runCount = newCount; % Set run count to the new value
    save(runCountFilePath, 'runCount', 'lastSavedDate'); % Save updated run count and last saved date
end

% TO MANUALLY CHANGE RUN COUNT:  >> setRunCount(n)    n = INTEGER
%setRunCount(1); % Reset the run count to 1 or any specific value
