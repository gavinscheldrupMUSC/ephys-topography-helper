function setRunCount(newCount, newUnsuccessfulAttemptCount)
    runCountFilePath = 'runCount.mat';
    
    % Check if the file exists
    if exist(runCountFilePath, 'file')
        % Load all variables from the file
        data = load(runCountFilePath);
        
        % Initialize missing variables
        if ~isfield(data, 'runCount')
            runCount = 0;
        else
            runCount = data.runCount;
        end
        
        if ~isfield(data, 'lastSavedDate')
            lastSavedDate = datestr(now, 'mmddyyyy');
        else
            lastSavedDate = data.lastSavedDate;
        end
        
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
        
        if ~isfield(data, 'unsuccessfulAttemptCount')
            unsuccessfulAttemptCount = 0;
        else
            unsuccessfulAttemptCount = data.unsuccessfulAttemptCount;
        end
        
        % Set all counts to the new value (if provided), or reset to 0
        if newCount == 0
            runCount = 0;
            protocolCounter = 0;
            reRecordCount = 0;
            unsuccessfulAttemptCount = 0;
        else
            runCount = newCount;
        end
        
        % If the new unsuccessful attempt count is provided, update it
        if nargin > 1
            unsuccessfulAttemptCount = newUnsuccessfulAttemptCount;
        end
        
        % Save all variables back to the file
        save(runCountFilePath, 'runCount', 'lastSavedDate', 'protocolCounter', 'reRecordCount', 'unsuccessfulAttemptCount');
        
        disp(['Run count has been set to ', num2str(runCount)]);
        disp(['Protocol counter has been set to ', num2str(protocolCounter)]);
        disp(['Re-record count has been set to ', num2str(reRecordCount)]);
        disp(['Unsuccessful attempt count is now ', num2str(unsuccessfulAttemptCount)]);
    else
        error('Run count file does not exist.');
    end
end
