function setRunCount(newCount)
    runCountFilePath = 'runCount.mat';
    if exist(runCountFilePath, 'file')
        load(runCountFilePath, 'runCount', 'lastSavedDate');
        runCount = newCount; % Set run count to the new value
        save(runCountFilePath, 'runCount', 'lastSavedDate'); % Save updated run count
        disp(['Run count has been set to ', num2str(runCount)]);
    else
        error('Run count file does not exist.');
    end
end
