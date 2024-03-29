% [output_struct, [WARNINGS]] = LMTF_generate_module_data_public(data, [PLOTFITS], [input_struct])
%
% This code fits the model of contrast sensitivity described in
% Gelfand, E. C., & Horwitz, G. D. (2018). Model of parafoveal chromatic
% and luminance temporal contrast sensitivity of humans and monkeys. 
% Journal of vision, 18(12), 1-1.
% 
% INPUT
%     data: n x 5 array [L, M, TF, OOG, RFx, RFy]
%          L and M are in cone contrast
%          TF is temporal frequency in Hz
%          OOG (out of gamut) is boolean (0 = in gamut)
%          RFx and RFy stimulus center location are in tenths of degrees
%     plotfits: true or false (false by default)
%     input_struct: output from a previous call to this function.
%         Useful for repeated calls when the data are minimally changed.
% OUTPUT
%     output_struct
%     warnings
%
% The algorithm is as follows:
% 1) quickLMTFfit for each retinal location to get a separate 13 parameter
% model for each.
%
% 2) Use the fitted model parameters from each retinal location as initial
% guesses to improve all the other fits until this no longer improves any
% of them. These are the "firstround" fits. If called with optional
% parameter, "input_struct" these first two steps are skipped and
% input_struct.legacy.firstroundmodels is used (CleanupFirstRoundFits 
% is called but should not take long because the individual fits have
% already been optimized). 
%
% 4) A variety of models are then fit: 
% "mode1": xi_lum, theta, and xi_rg are allowed to vary across locations
%      The initial guess for the 10 shared parameters is obtained by fitting
%      a weighted (by #observations) sum of fits over all locations. 
% "mode0": xi_lum and xi_rg are allowed to vary across retinal locations
% "mode1p1": xi_lum, n_lum, and xi_rg are allowed to vary across locations
% "mode1p2": xi_lum, xi_rg, n_rg are allowed to vary across locations
% "mode2": xi_lum and xi_rg are allowed to vary across locations according
% to a parametric model. 
%
% (Note: empirically, mode 0 works well which is why mode1p1 and mode1p2
% are refit with initial guesses dereived from the mode0 fit).
%
% These models are refit until the less constrained models fit better than
% the more constrained models.
% 
% Then, additional models are fit that include a dependence of some parameters  
% with retinal position:
%
% 6) Fit a 18 parameter model (mode 3) in which 11 parameters are shared across
% retinal locations (all but xi_lum and xi_rg) and xi_lum and xi_rg are
% functions of eccentricity: log10(xi_LUM) = b1*r+b2*sin(2*phi)+b3*cos(2*phi)+b0
% (4 parameters). log10(xi_RG) =  a1*r+a2*cos(2*phi)+a0 (3 parameters).
% This is the "tilted rampy trough" model (LUM only allowed to tilt).
%
% 7) Fit a 19 parameter model (mode 4) in which 11 parameters are shared across
% retinal locations (all but xi_lum and xi_rg) and xi_lum and xi_rg are
% functions of eccentricity: log10(xi_LUM) = b1*r+b2*sin(2*phi)+b3*cos(2*phi)+b0
%(4 parameters). log10(xi_RG) =  a1*r+a2*sin(2*phi)+a3*cos(2*phi)+a0 (4 parameters).
% This is the "tilted rampy trough" model (both LUM and RG allowed to tilt).
%
% 8) Fit a 18 parameter model (mode 5) in which 11 parameters are shared across
% retinal locations (all but xi_lum and xi_rg) and xi_lum and xi_rg are
% functions of eccentricity: log10(xi_LUM) = b1*r+b2*sin(2*phi)+b3*cos(2*phi)+b0
%(4 parameters). log10(xi_RG) =  a1*r+b2*sin(2*phi)+a3*cos(2*phi)+a0 (3 parameters).
% This is the "yoked tilted rampy trough" model (both LUM and RG constrained to
% have the same tilt).
%
% Previously, we used phi^2 and phi instead of cos(2*phi) and sin(2*phi) to
% model the horizontal/vertical anisotropy (previously phi^2, now cos(2*phi))
% and the tilt (previously phi, now sin(2*phi) because the old way
% predicted unrealisitically high thresholds along the vertical meridian.
%
% 2014/10/02 zlb - Original version
% 2015/05/19 zlb - Can now fit n models, where n is the # of eccentricities
% 2015/09/14 zlb - Fitting procedure now fits two 1-D CRFs -> 2-D -> full model
% 2015/12/14 zlb - Adding the append feature to update the .mat file in place
% 2016/05/06 gdlh - switching over to 17 parameter model. No longer supporting append
% mode.
% 2016/08/31 gdlh - setting the slope parameter for theta to zero in the
% event that the relationhip between theta and functional eccentricity
% ends up being non-significant.
% 2016/11/03 eg - converted to DB flist input
% 2017/2/10 gdlh - changing mode 1 parameterization and removing dependence
% of theta on retinal position. Also adding mode 4.
% 2017/3/06 eg - added mode 5.
% 2017/4/14 eg - shortened, made mode5 primary model, added params to
% output struct
% 2017/5/2 gdlh - changed how parameter bounds are passed around.
% 2017/6/14 gdlh - changed tilted trough from being parameterized by phi^2 and 
% phi to cos(2*phi) and sin(2*phi)

function [output_struct, WARNINGS] = LMTF_generate_module_data_public(data, PLOTFITS, input_struct)
try
    WARNINGS = {}; % Keeping track of any warnings that come up during the run
    if (nargin < 3)
        input_struct = {};
    end
    if (nargin < 2)
        PLOTFITS = false;
    end
    STIM_XY = [5 6]; % Indices in the "data" matrix
    
    USEFMINSEARCHBND = false; % Setting this to true produced worse fits for monkey 1 (Apollo)
    if USEFMINSEARCHBND
        options = optimset('MaxFunEvals',10^6,'MaxIter', 5e4);
    else
        options = optimoptions('fmincon','Algorithm', 'active-set', 'MaxFunEvals',10^6, ...
            'MaxIter', 5e4, 'TolFun', 1e-8, 'TolX', 0, 'Display', 'final');
    end
    output_struct = struct;
    % --------------------------------------------------
    % Looping over retinal locations,
    % fitting each data set with an independent 13-parameter mdoel
    % --------------------------------------------------
    uniqueXYs = unique(data(:,STIM_XY), 'rows','stable');
    if (size(uniqueXYs,1) < 3)
        error('Fewer than 3 eccentricities sampled; skipping.');
    end
    if (rank(uniqueXYs) == 1)
        error('Only colinear retinal positions sampled; skipping.');
    end
    % First, getting quick fits to data at each location
    % (Only do this if model parameters have not yet been passed in)
    nuniqueXYs = size(uniqueXYs,1);
    models = []; % stores the 13-parameter fits
    domain = [];fvs = [];
    if (isempty(input_struct))
        waitbar_h = waitbar(0,'Initial, quick fits. Please wait...');
        for m = 1:nuniqueXYs
            waitbar(m/nuniqueXYs,waitbar_h,['Initial, quick fits. Please wait... RF (',num2str(uniqueXYs(m,1)),', ',num2str(uniqueXYs(m,2)),')']);
            Lecc = all(data(:,STIM_XY) == repmat(uniqueXYs(m,:),size(data,1),1),2);
            [tmpmodel, ~, fv] = quickLMTFmodelfit(data(Lecc,1:4));
            if (isnan(fv)) % Getting rid of retinal locations with too few data points
                WARNINGS{length(WARNINGS)+1} = sprintf('RF (%d, %d) skipped. quickLMTFmodelfit failed. Too few data points?', uniqueXYs(m,:));
                data(Lecc,:) = [];
            else
                models = [models, tmpmodel'];
                fvs = [fvs, fv];
                domain = [domain, [-max(abs(data(:,1))) -max(abs(data(:,2))) min(data(:,3)) max(abs(data(:,1))) max(abs(data(:,2))) max(data(:,3))]']; % needed for IsoSamp
            end
        end
        close (waitbar_h);
    else % if input_struct has been passed in, use it - don't recalculate the first round models (in which each location is independent).
        models = input_struct.legacy.firstroundmodels;
        fvs = input_struct.legacy.firstroundfvs;
    end
    uniqueXYs = unique(data(:,STIM_XY), 'rows','stable'); % need to recalculate this because we may have removed some retinal locations
    if ~isempty(input_struct) % getting rid retinal locations and data for which we don't have enough threshold measurements
        uniqueXYs = uniqueXYs(ismember(uniqueXYs, input_struct.eccs,'rows'),:);
        data = data(ismember(data(:,[5 6]),uniqueXYs,'rows'),:);
    end
    nuniqueXYs = size(uniqueXYs,1); % need to recalculate this because we may have removed some retinal locations
    [firstroundmodels, ~] = CleanupFirstRoundFits(uniqueXYs, data, models, fvs); % Nested. Just improving all of the fits.
    
    % --------------------------------------------------
    % Now that we have an independent 13-parameter model
    % fit at each location, we are going to fit a more
    % constrained model in which the 10 shape parameters
    % are fixed and the remaining three parameters (xi_lum,
    % xi_rg, and theta) are free to vary independently
    % across retinal locations.
    % --------------------------------------------------
    % First getting estimates of the 10 shared parameters
    % by fitting a weighted average of cuts through the individual
    % threshold surfaces.
    % getting numbers of data points per retinal location
    ns = zeros(nuniqueXYs,1);
    for i = 1:nuniqueXYs
        ns(i) = sum(all([data(:,STIM_XY(1)) == uniqueXYs(i,1), data(:,STIM_XY(2)) == uniqueXYs(i,2)],2));
    end
    % Sampling from the models over a reasonable range of temporal
    % frequencies and fitting these sampled functions.
    % Note: this code assumes that the 3rd column of data is the
    % temporal frequency and 4th is the boolean out of gamut vector.
    Loog = data(:,4);
    tfs = logspace(log10(min(data(:,3))),log10(prctile(data(~Loog,3),90)),40);
    % Computing weighted (by n) averages of predicted thresholds
    modelfits = zeros(nuniqueXYs,length(tfs),2);
    for i = 1:2 % LUM/RG
        for j = 1:nuniqueXYs
            if (i == 1)
                xi = firstroundmodels(1,j);
                zeta = firstroundmodels(2,j);
                n1 = firstroundmodels(3,j);
                n2 = firstroundmodels(3,j)+firstroundmodels(4,j);
                tau1 = 10^firstroundmodels(5,j);
                tau2 = 10^(firstroundmodels(5,j)+firstroundmodels(6,j));
            else
                xi = firstroundmodels(7,j);
                zeta = firstroundmodels(8,j);
                n1 = firstroundmodels(9,j);
                n2 = firstroundmodels(9,j)+firstroundmodels(10,j);
                tau1 = 10^firstroundmodels(11,j);
                tau2 = 10^(firstroundmodels(11,j)+firstroundmodels(12,j));
            end
            f = @(omega)xi*abs(((1i*2*pi*tau1.*omega+1).^-n1)-zeta*((1i*2*pi*tau2.*omega+1).^-n2));
            modelfits(j,:,i) = f(tfs);
        end
    end
    %  1D model fits to weighted averages
    boundList = boundsSorter('mode1d');
    LB = boundList(:,1)';
    UB = boundList(:,2)';
    initparams(1,:) = [20  .9  3 -0.1 -2 log10(1.5)]; % LUM
    initparams(2,:) = [100 .1 10 -0.1 -2 log10(1.1)]; % RG
    wtavg = zeros(2,length(tfs));
    params = zeros(2,6); % 2 color directions, 6 parameters for 1D fit
    %options.TypicalX = mean(initparams);
    for i = 1:2
        wtavg(i,:) = ns'*squeeze(modelfits(:,:,i))./sum(ns);
        if USEFMINSEARCHBND
            params(i,:) = fminsearchbnd(@(x) tf_fiterr(x,tfs,wtavg(i,:)),initparams(i,:),...
                LB,UB,options);
        else
            params(i,:) = fmincon(@(x) tf_fiterr(x,tfs,wtavg(i,:)),initparams(i,:),...
                [],[],[],[],LB,UB,[],options);
        end
    end
    
    % Initial guesses for the big minimization problem: identical contrast
    % sensitivity functions everywhere, but gains are allowed to change
    %initialguess = MakeParamList([params(1,2:end)';params(2,2:end)'],firstroundmodels([1 7 13],:));
    initialguess = MakeParamList([params(1,2:end)';params(2,2:end)'],[firstroundmodels([1 7],:); repmat(pi/4,1,nuniqueXYs)]);
    % 2/15/17 At the end of the procedure:
    % Mode 1 (10+3n) should have less error than mode 0 (11+2n)
    % Mode 1 (10+3n) should have less error than mode 2 (rampy trough)
    % Mode 1.1 (10+3n) should have less error than mode 0 (11+2n)
    % Mode 1.1 (10+3n) should have less error than mode 2 (rampy trough)
    % Mode 2 (rampy trough) should have less error than mode 0 (11+2n) (this
    % version of rampy trough doesn't allow theta to vary)
    % Mode 3 (tilted rampy trough) should have less error than mode 2 (rampy trough)
    % Mode 4 (double tilted rampy trough) should have less error than mode 3 (tilted rampy trough)
    % Mode 5 (yoked double tilted rampy trough) should have less error than
    % Mode 3 (tilted rampy trough), unknown whether more or less error than mode 4
    
    % Start of a while loop here so that we come here (with improved initial guesses) if
    % the third round model fits the data better than the second round model.
    mode0fvs = 0; mode1fvs = 1; mode2fvs = 0; % to make sure we get inside the 'while' the first time
    while sum(mode2fvs) < sum(mode0fvs) ||  sum(mode0fvs) < sum(mode1fvs)
        % First Mode 1 fit (10+3*n)(xi_lum, xi_rg, theta)
        [mode1models, mode1fvs, ~] = modelTest(initialguess, 1);
        % First Mode 1.1 fit (10+3*n) (xi_lum, n_lum, xi_rg)
        initialguess = MakeParamList([mode1models([2,4:6,8:12],1); mean(mode1models(13,:))],mode1models([1 3 7],:));
        modelTest(initialguess,1.1);
        % First Mode 1.2 fit (10+3*n) (xi_lum, n_rg, xi_rg)
        initialguess = MakeParamList([mode1models([2:6,8,10:12],1); mean(mode1models(13,:))],mode1models([1 7 9],:));
        modelTest(initialguess,1.2);
        % Mode 0 fit (11+2*n) (xi_lum, xi_rg)
        initialguess = MakeParamList([mode1models([2:6,8:12],1); mean(mode1models(13,:))], mode1models([1 7],:));
        [mode0models, mode0fvs, fpar0] = modelTest(initialguess,0);
        % Emily: Here's the new code.
        % Second Mode 1 fit (10+3*n)(xi_lum, xi_rg, theta)
        initialguess = MakeParamList(mode0models([2:6,8:12],1), mode0models([1 7 13],:));
        [mode1models2, mode1fvs2, ~] = modelTest(initialguess,1);
        % Second Mode 1.1 fit (10+3*n)(xi_lum, n_lum, xi_rg)
        initialguess = MakeParamList([mode0models([2,4:6,8:12],1); mean(mode0models(13,:))],mode0models([1 3 7],:));
        modelTest(initialguess,1.1);
        % Second Mode 1.2 fit (10+3*n)(xi_lum, xi_rg, n_rg)
        initialguess = MakeParamList([mode0models([2:6,8,10:12],1); mean(mode0models(13,:))],mode0models([1 7 9],:));
        modelTest(initialguess,1.2);
        % --------------------------------------------------
        % Now using mode 0 fit (11 fixed parameters, 2 free to vary at will)
        % as initial guess for a 17 parameter model (11 fixed parameters
        % that control the shape of the temporal contrast sensitivity function
        % and theta. Six additional parameters that control how xi_lum and xi_rg
        % vary across retinal position according to a symmetric rampy trough.
        % (Mode 2)
        % --------------------------------------------------
        [phi,r] = cart2pol(abs(uniqueXYs(:,1))/10,uniqueXYs(:,2)/10);
        mode2fvs = Inf;
        for initialguess_idx = 1:3
            if initialguess_idx == 1 % regress
                b = regress(log10(mode0models(1,:))',[ones(size(r)), r, r.*cos(2*phi)]); % xi_LUM. order of parameters: b0, br, bphi
                a = regress(log10(mode0models(7,:))',[ones(size(r)), r, r.*cos(2*phi)]); % xi_RG. order of parameters: b0, br, bphi
            elseif initialguess_idx == 2 % lscov
                b = lscov([ones(size(uniqueXYs,1),1) [r r.*cos(2*phi)]],log10(mode0models(1,:))',ns);
                a = lscov([ones(size(uniqueXYs,1),1) [r r.*cos(2*phi)]],log10(mode0models(7,:))',ns);
            else  % robustfit, which automatically prepends a vector of 1s
                b = robustfit([r r.*cos(2*phi)],log10(mode0models(1,:))');
                a = robustfit([r r.*cos(2*phi)],log10(mode0models(7,:))');
            end
            initialguess = [fpar0(1:11); b(1); b(2); b(3); a(1); a(2); a(3)];
            % Order of parameters
            % [zeta_1, n1, delta_n1, tau1, kappa1, zeta_2, n2, delta_n2, tau2, kappa2, theta] <-- first 11
            % [b0, b1, b2, a0, a1, a2]
            modelTest(initialguess, 2);
            %   if sum(tmp_mode2fvs) < sum(mode2fvs)
            %       mode2models = tmp_mode2models;
            %       mode2fvs = tmp_mode2fvs;
            %       fpar2 = tmp_fpar2;
            %   end
        end
        %if the fit using mode0models is better than the previous fit,
        %save only the better fit
        if sum(mode1fvs2) < sum(mode1fvs)
            mode1models = mode1models2;
            mode1fvs = mode1fvs2;
        end
        if sum(mode2fvs) < sum(mode0fvs)
            % Setting up a new initial guess for a new rampy trough fit
            % based on an inferior 11+2n fit
            initialguess = MakeParamList(mode2models([2:6,8:12],1), mode2models([1 7 13],:));
            % [zeta_LUM, n1_LUM, delta n_LUM, tau1_LUM, kappa_LUM, zeta_RG, n1_RG,...
            % delta n_RG, tau1_RG, kappa_RG];
            % Note, at this point some parameters might be out of bounds (e.g. theta).
            WARNINGS{length(WARNINGS)+1} = 'Mode 2 model fit better than mode 0 model. Repeating fitting with new initial guesses.';
        end
        if sum(mode0fvs) < sum(mode1fvs)
            % [zeta_LUM, n1_LUM, delta n_LUM, tau1_LUM, kappa_LUM, zeta_RG, n1_RG,...
            % delta n_RG, tau1_RG, kappa_RG, theta];
            initialguess = MakeParamList(mode0models([2:6,8:12],1),mode0models([1 7 13],:));
            WARNINGS{length(WARNINGS)+1} = 'Mode 0 model (11+2n) fit better than mode 1 model (10+3n). Repeating fitting with new initial guesses.';
        end
    end % end of while loop that fits mode 0, 1, 1.1, 1.2, and 2 models until fv(1) > fv(0) > fv(2)
    % ------------------------------------------------------------
    % Below, fitting the mode 3 model (asymmetric rampy trough).
    % r and phi have already been defined. Only luminance can tilt.
    % ------------------------------------------------------------
    mode3fvs = Inf;
    disp('Fitting model3')
    for initialguess_idx = 0:3
        if initialguess_idx == 0 % use the mode 2 fit with a coefficient on phi (xi_lum) of 0
            fpar2 = output_struct.legacy.mode2params;
            mode2models = output_struct.legacy.mode2models;
            initialguess = [fpar2(1:13); 0; fpar2(14:17)];
        elseif initialguess_idx == 1 % regress
            b = regress(log10(mode0models(1,:))',[ones(size(r)) r r.*sin(2*phi) r.*cos(2*phi)]);
            a = regress(log10(mode0models(7,:))',[ones(size(r)), r r.*cos(2*phi)]);
            initialguess = [mode0models([2:6,8:13],1); b; a];
        elseif initialguess_idx == 2 % lscov
            b = lscov([ones(size(uniqueXYs,1),1) [r r.*sin(2*phi) r.*cos(2*phi)]],log10(mode0models(1,:))',ns);
            a = lscov([ones(size(uniqueXYs,1),1) [r r.*cos(2*phi)]],log10(mode0models(7,:))',ns);
            initialguess = [mode0models([2:6,8:13],1); b; a];
        elseif initialguess_idx == 3  % robustfit, which automatically prepends a vector of 1s
            b = robustfit([r r.*sin(2*phi) r.*cos(2*phi)],log10(mode0models(1,:))');
            a = robustfit([r r.*cos(2*phi)],log10(mode0models(7,:))');
            initialguess = [mode0models([2:6,8:13],1); b; a];
        end
        [~, tmp_mode3fvs, tmp_fpar3] = modelTest(initialguess, 3);
        if sum(tmp_mode3fvs) < sum(mode3fvs)
            mode3fvs = tmp_mode3fvs; % Just for debugging
            fpar3 = tmp_fpar3;
        end
    end
    % Mode 5 models. Tilted rampy trough in which both lum and rg are allowed
    % to tilt, but the tilt is fixed for both.
    disp('Fitting model5')
    
    mode5fvs = Inf;
    for initialguess_idx = 0:3
        if initialguess_idx == 0 % use the mode 3 fit with a coefficient on sin(2*phi) of 0 for rg
            initialguess = fpar3; % only difference between mode 3 and 5 is how parameter 14 is used
        elseif initialguess_idx == 1 % regress
            Ys = [log10(mode0models(1,:))'; log10(mode0models(7,:))'];
            Xs = [ones(size(r,1),1), r, r.*sin(2*phi), r.*cos(2*phi), zeros(size(r,1),3)];
            Xs = [Xs; zeros(size(r,1),2), r.*sin(2*phi), zeros(size(r,1),1), ones(size(r,1),1), r, r.*cos(2*phi)];
            b = regress(Ys,Xs); % order of params: b0, b1, b2, b3, a0, a1, a3
            initialguess = [mode2models([2:6,8:13],1); b];
        elseif initialguess_idx == 2 % lscov
            b = lscov(Xs,Ys,[ns; ns]);
            initialguess = [mode2models([2:6,8:13],1); b];
        else  % robustfit, which automatically prepends a vector of 1s which we then remove
            b = robustfit(Xs, Ys, [],[],'off');
            initialguess = [mode2models([2:6,8:13],1); b];
        end
        modelTest(initialguess, 5);
    end
    % Mode 4 models. Tilted rampy trough in which both lum and rg are allowed
    % to tilt independently
    mode4fvs = Inf;
    try
        fpar5 = output_struct.legacy.mode5params; % for initial guess
    catch
        keyboard
    end
    for initialguess_idx = 0:4
        if initialguess_idx == 0 % use the mode 5 fit as the initial guess
            initialguess = [fpar5(1:17); fpar5(14); fpar5(18)];
        elseif initialguess_idx == 1 % regress
            b = regress(log10(mode0models(1,:))',[ones(size(r)) r r.*sin(2*phi) r.*cos(2*phi)]);
            a = regress(log10(mode0models(7,:))',[ones(size(r)), r r.*sin(2*phi) r.*cos(2*phi)]);
            initialguess = [mode2models([2:6,8:13],1); b; a];
        elseif initialguess_idx == 2 % lscov
            b = lscov([ones(size(uniqueXYs,1),1) [r r.*sin(2*phi) r.*cos(2*phi)]],log10(mode0models(1,:))',ns);
            a = lscov([ones(size(uniqueXYs,1),1) [r r.*sin(2*phi) r.*cos(2*phi)]],log10(mode0models(7,:))',ns);
            initialguess = [mode2models([2:6,8:13],1); b; a];
        elseif initialguess_idx == 3  % robustfit, which automatically prepends a vector of 1s
            b = robustfit([r r.*sin(2*phi) r.*cos(2*phi)],log10(mode0models(1,:))');
            a = robustfit([r r.*sin(2*phi) r.*cos(2*phi)],log10(mode0models(7,:))');
            initialguess = [mode2models([2:6,8:13],1); b; a];
        else
            initialguess = [fpar3(1:17); 0; fpar3(18)]; % GDLH added 4/3/17 to avoid mode4fv > mode3fv. Use mode 3 as initial guess
        end
        modelTest(initialguess, 4);
    end
    mode5fv = tf_fiterr3(output_struct.legacy.mode5params,data,5);
    mode4fv = tf_fiterr3(output_struct.legacy.mode4params,data,4);
    mode3fv = tf_fiterr3(output_struct.legacy.mode3params,data,3);
    mode2fv = tf_fiterr3(output_struct.legacy.mode2params,data,2);
    
    if mode5fv < mode4fv % error: yoked has smaller error than double!
        keyboard
    end
    
    % Sanity check. Could delete. This can't happen because we use the nested
    % model parameters as an initial guess for the rich model.
    if (mode4fv > mode3fv) || (mode3fv > mode2fv)
        disp('A constrained fit has lower error than a flexible fit!');
        keyboard
    end
    
    % Getting the raw data (needed by LMTFbrowser.m)
    for i = 1:nuniqueXYs
        L = all(data(:,STIM_XY) == repmat(uniqueXYs(i,:),size(data,1),1),2);
        output_struct.raw{i} = data(L,:);
    end
    output_struct.eccs = uniqueXYs;
    output_struct.domain = max(domain,[],2);
    
    if ~isempty(WARNINGS)
        disp('The following warnings occured:');
        for i = 1:length(WARNINGS)
            disp(WARNINGS{i});
        end
    end
    
    if any(isnan(fvs))
        keyboard
    end
catch
    keyboard
end
    function paramList = boundsSorter(model_mode)
        bounds.xi = [1 500]; %  Changed LB from 0 to 1 to avoid log10(0) error. "1" is a very low sensitivity.
        bounds.zeta = [0 1];
        bounds.n = [1 10];
        bounds.delta_n = [0 6];
        bounds.logtau = [-3 -1];
        bounds.logkappa = [log10(1.00001) .5];
        bounds.theta = [0 pi/2];
        bounds.a = [-10 10];
        bounds_base = [bounds.xi; bounds.zeta; bounds.n; bounds.delta_n; bounds.logtau; bounds.logkappa; bounds.theta]; % 7 params
        bounds_early = [bounds_base(1:end-1,:); bounds_base]; % 13 params
        bounds_later = [bounds_base(2:end-1,:); bounds_base(2:end,:)]; % 11 params
        switch model_mode
            case 'frf'
                paramList = bounds_early;
            case 'mode1d'
                paramList = bounds_base(1:end-1,:);
            case 'mode1'
                paramList = [bounds_later(1:end-1,:); repmat([bounds.xi; bounds.xi; bounds.theta],nuniqueXYs,1)];
            case 'mode1p1'
                paramList = [bounds_base([2,4:6],:); bounds_base([2:7],:); repmat([bounds.xi; bounds.n; bounds.xi;],nuniqueXYs,1)];
            case 'mode1p2'
                paramList = [bounds_base([2:6],:); bounds_base([2,4:7],:); repmat([bounds.xi; bounds.xi; bounds.n;],nuniqueXYs,1)];
            case 'mode0'
                paramList = [bounds_later; repmat([bounds.xi; bounds.xi],nuniqueXYs,1)];
            case 'mode2'
                paramList = [bounds_later; repmat(bounds.a, 6, 1)];
            case 'mode4'
                paramList = [bounds_later; repmat(bounds.a,8,1)];
            case 'mode3'
                paramList = [bounds_later; repmat(bounds.a,7, 1)];
            case 'mode5'
                paramList = [bounds_later; repmat(bounds.a,7, 1)];
            otherwise
                error('Unknown model mode');
        end
    end

    function [model,fvs, fpar] = modelTest(initialguess, model_mode)
        if model_mode == 1.1
            model_name = 'mode1p1models';
            fv_name = 'mode1p1fvs';
            param_name = 'mode1p1params';
        elseif model_mode == 1.2
            model_name = 'mode1p2models';
            fv_name = 'mode1p2fvs';
            param_name = 'mode1p2params';
        else
            model_name = sprintf('mode%dmodels', model_mode);
            fv_name = sprintf('mode%dfvs', model_mode);
            param_name = sprintf('mode%dparams', model_mode);
        end
        paramList = boundsSorter(model_name(1:end-6));
        LB = paramList(:,1)';
        UB = paramList(:,2)';
        if size(paramList,1) ~= length(initialguess)
            keyboard
        end
        % If the initial guess is already better than what we already
        % have, use it.
        % Important to do this before changing the initial guess.
        try
            if model_mode >=2 
                [~,fvs] = tf_fiterr3(initialguess,data,model_mode);
                if ~isfield(output_struct.legacy, fv_name) || sum(fvs) <  sum(output_struct.legacy.(fv_name))
                    model = [];
                    for n = 1:nuniqueXYs
                        model = [model, LMTF_global_to_local_model(initialguess, uniqueXYs(n,1)/10,uniqueXYs(n,2)/10,model_mode)];
                    end
                    output_struct.legacy.(param_name) = initialguess;
                    output_struct.legacy.(model_name) = model; % all local models
                    output_struct.legacy.(fv_name) = fvs;
                end
            end
            % Done checking the initial guess
        catch
            keyboard
        end
        model = []; fvs = [];
        if any(LB' >= initialguess)
            L = LB' >= initialguess; 
            initialguess(L) = LB(L) + (UB(L)-LB(L))./1000;
        end
        if any(UB' <= initialguess)
            L = UB' <= initialguess;
            initialguess(L) = UB(L) - (UB(L)-LB(L))./1000;
        end
        typical_x = initialguess;
        typical_x(typical_x == 0) = 1e-10;

        options.TypicalX = typical_x; % This appears to be important (active-set fmincon)
        if any(LB' >= initialguess | UB' <=initialguess) % unnecessary
            keyboard
        end
        if USEFMINSEARCHBND
            [fpar,fv, exitflag] = fminsearchbnd(@(params) tf_fiterr3(params,data,model_mode),initialguess,LB,UB,options);
        else
            [fpar,fv, exitflag] = fmincon(@(params) tf_fiterr3(params,data,model_mode),initialguess,[],[],[],[],LB,UB,[],options);
        end
        if exitflag < 1
            WARNINGS{length(WARNINGS)+1} = sprintf('mode %d model did not converge. Exitflag = %d', model_mode, exitflag);
        end
        if PLOTFITS %all models
            figure; axes; hold on; plot(LB,'b-'); plot(UB,'r-'); plot(fpar,'g.');
        end
        if model_mode < 2
            if model_mode == 0
                ximat = reshape(fpar(12:end),2,nuniqueXYs);
                for n=1:nuniqueXYs
                    model(:,n) = [ximat(1,n);fpar(1:5); ximat(2,n); fpar(6:11)];
                end
            elseif model_mode == 1
                ximat = reshape(fpar(11:end),3,nuniqueXYs);
                for n=1:nuniqueXYs
                    model(:,n) = [ximat(1,n);fpar(1:5); ximat(2,n); fpar(6:10); ximat(3,n)];
                end
            elseif model_mode == 1.1 
                ximat = reshape(fpar(11:end),3,nuniqueXYs);
                for n=1:nuniqueXYs
                    model(:,n) = [ximat(1,n); fpar(1); ximat(2,n); fpar(2:4); ximat(3,n); fpar(5:10)];
                end
            elseif model_mode == 1.2
                ximat = reshape(fpar(11:end),3,nuniqueXYs);
                for n=1:nuniqueXYs
                    model(:,n) = [ximat(1,n); fpar(1:5); ximat(2,n); fpar(6); ximat(3,n); fpar(7:10)];
                end
            else
                error('Unknown model type');
            end
            for n = 1:nuniqueXYs % getting individual fvs on a per location basis
                Lecc = all(data(:,STIM_XY) == repmat(uniqueXYs(n,:),size(data,1),1),2);
                fvs(n) = tf_fiterr2(model(:,n),data(Lecc,1:4));
            end
        else
            for n = 1:nuniqueXYs % use global to local model here
                localmodel = LMTF_global_to_local_model(fpar, uniqueXYs(n,1)/10,uniqueXYs(n,2)/10,model_mode);
                model = [model, localmodel];
                Lecc = all(data(:,STIM_XY) == repmat(uniqueXYs(n,:),size(data,1),1),2);
                fvs = [fvs, tf_fiterr2(localmodel,data(Lecc,1:4))];
            end
        end
        if (sum(fvs)-fv > 10^-8)
            disp('Disagreement between global error and sum of local errors');
            keyboard
        end
        if ~isfield(output_struct.legacy, fv_name) || sum(fvs) <  sum(output_struct.legacy.(fv_name))
            output_struct.legacy.(param_name) = fpar;
            output_struct.legacy.(model_name) = model; % all local models
            output_struct.legacy.(fv_name) = fvs;
            if any(isnan(fvs))
                keyboard
            end
        end
    end
% Fitting each dataset (data at each retinal location) using as an initial
% guess the best fit from each other data sets. Continue until none of the
% fits improve. From GrantBrainStorming Section 4.16
    function [outmodels, fvs] = CleanupFirstRoundFits(uniqueXYs, data, inmodels, fvs)
        paramList = boundsSorter('frf');
        LB = paramList(:,1)';
        UB = paramList(:,2)';
        initialguessidxs = 1:size(uniqueXYs,1);
        keepingtrack = 1; % Just need to start with some value in keeping track, it's cleared two lines below anyway
        % keepingtrack keeps track of which set of model parameters, used as an
        % initial guess, improves which model fit.
        waitbar_h = waitbar(0,'Please wait...');
        while ~isempty(keepingtrack)
            keepingtrack = [];
            for ii = 1:size(uniqueXYs,1) % data comes from retinal location i
                for jj = initialguessidxs % initial guess comes from model fit at location j
                    fractionalwaythrough = ((ii-1)*length(initialguessidxs)+find(jj==initialguessidxs))/(size(uniqueXYs,1)*length(initialguessidxs));
                    waitbar(fractionalwaythrough,waitbar_h);
                    Lecc = all(data(:,[5 6]) == repmat(uniqueXYs(ii,:),size(data,1),1),2);
                    % Just pulling out the data that's at the right retinal position (ecc).
                    %options.TypicalX = (UB-LB)./100;
                    % options.TypicalX = ones(length(UB),1);
                    if USEFMINSEARCHBND
                        [model,fv] = fminsearchbnd(@(params) tf_fiterr2(params,  data(Lecc,1:3),data(Lecc,4)), inmodels(:,jj),...
                            LB,UB,options);
                    else
                        [model,fv] = fmincon(@(params) tf_fiterr2(params,  data(Lecc,1:3),data(Lecc,4)), inmodels(:,jj),...
                            [],[],[],[],LB,UB,[],options);
                    end
                    if (fv < fvs(ii))
                        disp('--------------------------------');
                        fprintf('Fit to data at (%d, %d) is improved by guessing model params from (%d, %d)\n',uniqueXYs(ii,:),uniqueXYs(jj,:));
                        fprintf('Fitting error decreased from %d to %d\n',fvs(ii),fv)
                        disp('--------------------------------');
                        inmodels(:,ii) = model;
                        fvs(ii) = fv;
                        keepingtrack = [keepingtrack; ii jj];
                    end
                end
            end
            % The first column of keepingtrack contains models that were updated in
            % the last round. Use these as initial guesses in nest round.
            if (~isempty(keepingtrack))
                initialguessidxs = unique(keepingtrack(:,1))';
                disp('Improved model fits at retinal locations');
                disp(uniqueXYs(initialguessidxs,:));
            end % otherwise, we're done
        end
        outmodels = inmodels;
        output_struct.legacy.firstroundmodels = outmodels;
        output_struct.legacy.firstroundfvs = fvs;
        close(waitbar_h);
    end

% Making a parameter list consisting of "fixed parameters", which
% appear once, as the top of the output vector, followed by the
% variable parameters one at a time.
    function list = MakeParamList(fixedparameters, variableparameters)
        if (size(fixedparameters,2) > 1) % forcing a column
            fixedparameters = fixedparameters';
        end
        suffix = [];
        for ii = 1:size(variableparameters,2)
            for jj = 1:size(variableparameters,1)
                suffix = [suffix; variableparameters(jj,ii)];
            end
        end
        list = [fixedparameters; suffix];
    end
end

%
% Below is a list of parameters and their order for the models that fix
% some parameters across the visual field.
% Mode 0 = 11+2n (Xi_lum and Xi_rg free to vary)
% Mode 1 = 10+3n (Xi_lum, theta, and Xi_rg free to vary)
% Mode 1.1 = 10+3n (Xi_lum, n_lum, and Xi_rg free to vary)
% Mode 1.2 = 10+3n (Xi_lum, Xi_rg, and n_rg free to vary)

% Mode 0
% 1: Zeta_lum
% 2: n_lum
% 3: delta_n_lum
% 4: Tau_lum
% 5: Kappa_lum
% 6: Zeta_lum
% 7: n_rg
% 8: delta_N_rg
% 9: Tau_rg
% 10: Kappa_rg
% 11: Theta
% 12: Xi_lum(location 1)
% 13: Xi_rg(location 1)
% 14: Xi_lum(location 2)
% 15: Xi_rg(location 2)...

% Mode 1
% 1: Zeta_lum
% 2: n_lum
% 3: delta_n_lum
% 4: Tau_lum
% 5: Kappa_lum
% 6: Zeta_lum
% 7: n_rg
% 8: delta_n_rg
% 9: Tau_rg
% 10: Kappa_rg
% 11: Xi_lum(location 1)
% 12: Xi_rg(location 1)
% 13: theta(location 1)
% 14: Xi_lum(location 2)
% 15: Xi_rg(location 2)
% 16: theta(location 1)...

% Mode 1.1
% 1: Zeta_lum
% 2: delta_n_lum
% 3: Tau_lum
% 4: Kappa_lum
% 5: Zeta_lum
% 6: n_rg
% 7: delta_n_rg
% 8: Tau_rg
% 9: Kappa_rg
% 10: theta
% 11: Xi_lum(location 1)
% 12: Xi_rg(location 1)
% 13: n_lum(location 1)
% 14: Xi_lum(location 2)
% 15: Xi_rg(location 2)
% 16: n_lum(location 1)...

% Mode 1.2
% 1: Zeta_lum
% 2: n_lum
% 3: delta_n_lum
% 4: Tau_lum
% 5: Kappa_lum
% 6: Zeta_lum
% 7: delta_n_rg
% 8: Tau_rg
% 9: Kappa_rg
% 10: theta
% 11: Xi_lum(location 1)
% 12: Xi_rg(location 1)
% 13: n_rg(location 1)
% 14: Xi_lum(location 2)
% 15: Xi_rg(location 2)
% 16: n_rg(location 1)...

