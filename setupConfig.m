function config = setupConfig()
    % This function creates and loads a configuration for the ephys script.
    
    configFile = 'ephys_config.mat';
    
    if exist(configFile, 'file')
        % Load existing configuration
        loadedConfig = load(configFile);
        config = loadedConfig.config;
        
        % Verify that folders still exist
        if ~isfield(config, 'imageFolder') || ~isfolder(config.imageFolder) || ...
           ~isfield(config, 'baseSaveFolder') || ~isfolder(config.baseSaveFolder)
            disp('A folder in the saved configuration is missing. Please re-select.');
            config = promptForFolders();
            save(configFile, 'config');
        end
    else
        % Prompt user for folders if no config file exists
        disp('First-time setup: Please select the required folders.');
        config = promptForFolders();
        save(configFile, 'config');
    end
    
    % --- Default settings that can also be in the config ---
    % Atlas image file extension (e.g., '*.jpg', '*.png', '*.tif')
    if ~isfield(config, 'atlasExtension')
        config.atlasExtension = '*.jpg'; 
    end
    
    % State file for run counts
    if ~isfield(config, 'runCountFilePath')
        config.runCountFilePath = 'runCount.mat';
    end
end

function config = promptForFolders()
    % Prompts user to select atlas and data-saving folders.
    
    imageFolder = uigetdir('', 'Select the folder containing your PFC Atlas images');
    if imageFolder == 0
        error('User cancelled folder selection. Cannot proceed.');
    end
    
    baseSaveFolder = uigetdir('', 'Select the base folder for saving E-phys data');
    if baseSaveFolder == 0
        error('User cancelled folder selection. Cannot proceed.');
    end
    
    config.imageFolder = imageFolder;
    config.baseSaveFolder = baseSaveFolder;
end