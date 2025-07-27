#!/usr/bin/env python3
# This is a scipt to generate plots data collected from the robots
# Assumptions:
# - Robot datasets are in folder data/Experiment_<tittle>/<robotID>
# Options:
# - If a flag is given then the data is plotted for each robot

import time
import os
import sys
import subprocess
import pandas as pd
from matplotlib import pyplot as plt
import glob
from graphviz import Digraph
import pydotplus
import networkx as nx
from networkx.algorithms.shortest_paths.generic import shortest_path as get_mainchain
import numpy as np
import seaborn as sns
from pathlib import Path

global tstart

datadir = '/home/cug/thesis/blockchain-simulations/FloorEstimation/results/data'
plotdir = '/home/cug/thesis/blockchain-simulations/FloorEstimation/results/plots'

def tic():
    global tstart
    tstart = time.time()
def toc():
    print(time.time()-tstart)  

def create_df(experiments, logfile, exclude_patterns = []):
    df_list = []
    experiments = [experiments] if isinstance(experiments, str) else experiments
    
    for experiment in experiments:
        
        # Make sure data and plot folder exists
        exp_plotdir = '%s/experiment_%s' % (plotdir, experiment)
        exp_datadir = '%s/experiment_%s' % (datadir, experiment)
        
        if not os.path.exists(exp_datadir):
            print("Dataset %s not found" % exp_datadir)
            continue
        
        if not os.path.exists(exp_plotdir):
          os.makedirs(exp_plotdir)
          print("New plot directory is created!")
        
        configs = sorted(glob.glob('%s/experiment_%s/*/' % (datadir, experiment)))

        if exclude_patterns:
            for exclude in exclude_patterns:
                configs = [config for config in configs if exclude not in config]

        for config in configs:
            csvfile_list = sorted(glob.glob('%s/*/*/%s.csv' % (config, logfile)))
            
            for csvfile in csvfile_list:
                df = pd.read_csv(csvfile, delimiter=" ")
                df['EXP'] = experiment 
                df['CFG'] = config.split('/')[-2]
                df['REP'] = csvfile.split('/')[-3]
                df = perform_corrections(df)
                df_list.append(df)
        
    if df_list:
        full_df = pd.concat(df_list, ignore_index=True)
        full_df.get_param = get_param_df
        return full_df
    else:
        return None

def get_param_df(df, param_dict, param, alias = None):
    df = df.groupby(['EXP','CFG','REP']).apply(lambda x: get_param(x, x.name , param_dict, param, alias))
    return df

def get_param(group, name, param_dict, param, alias):
    exp = name[0]
    cfg = name[1]
    rep = name[2]
    
    configfile = '%s/experiment_%s/%s/%s/config.py' % (datadir, exp, cfg, rep)
    exec(open(configfile).read(), globals())
    param_dict = eval(param_dict)
    if param in param_dict:
        if alias:
            group[alias] = repr(param_dict[param])
        else:
            group[param] = param_dict[param]
    return group

def get_config_dicts(exp,cfg,rep):
    configfile = '%s/experiment_%s/%s/%s/config.py' % (datadir, exp, cfg, rep)
#     print(open(configfile).read())
    with open(configfile) as f:
        for line in f:
            print(line)

    
def perform_corrections(df):

    if 'DIST' in df.columns:
        df['DIST'] = df['DIST']/100
        
    if 'RECRUIT_DIST' in df.columns:
        df['RECRUIT_DIST'] = df['RECRUIT_DIST']/100
        
    if 'SCOUT_DIST' in df.columns:
        df['SCOUT_DIST'] = df['SCOUT_DIST']/100
        
    if 'MB' in df.columns:
        df['MB'] = df['MB']*10e-6
        
    df['CONTROLLER'] = df['CFG'].str.split('_').str[-1]
    
    return df


# Construct digraph
def create_digraph(df):
    # Default settings for blockchain viz
    digraph = Digraph(comment='Blockchain', 
                      edge_attr={'arrowhead':'none'},
                      node_attr={'shape': 'record', 'margin': '0', 'fontsize':'9', 'height':'0.35', 'width':'0.35'}, 
                      graph_attr={'rankdir': 'LR', 'ranksep': '0.1', 'splines':'ortho'})
    

#     df.apply(lambda row : digraph.node(row['HASH'], str(row['BLOCK'])), axis = 1)
    digraph.node(df['PHASH'].iloc[0], '<f0> {} | <f1> {}'.format(df['PHASH'].iloc[0][2:6], 'Genesis'))
    df.apply(lambda row : digraph.node(row['HASH'], '<f0> {} | <f1> {}'.format(row['HASH'][2:6], str(row['BLOCK']))), axis = 1)
    df.apply(lambda row : digraph.edge(row['PHASH'], row['HASH']), axis = 1)
    
    return digraph

def get_mainchain_df2(df, leaf):
    mainchain = [leaf]
    main_path = []
    
    for (idx, row) in df[::-1].iterrows():
        if row['PHASH'] in main_path:
            main_path.append(idx)
        
    return df.iloc[main_path]


def get_mainchain_df(df, leaf):
    parentHash = leaf
    main_path = []
    
    for (idx, row) in df[::-1].iterrows():
        if row['HASH'] == parentHash:
            main_path.append(idx)
            parentHash = row['PHASH']
        
    return df.iloc[main_path]


def convert_digraph(digraph):
    return nx.nx_pydot.from_pydot(pydotplus.graph_from_dot_data(digraph.source))

# Remove childless blocks
def trim_chain(df, levels=1):
    sub_df = df
    while levels:
        sub_df = sub_df.query('HASH in PHASH')
        levels -= 1
    return sub_df

def paths_longer_than(paths, n):
    return [x for x in paths if len(x)>=n]

def nodes_in_paths(paths):
    return [item for sublist in paths for item in sublist]

###########################################################################
from scipy.optimize import curve_fit
def LinearRegression0(group, x, y):
    # objective function
    def model(x, a):
        return a * x
    coefs, _ = curve_fit(model, group[x], group[y])
    a = float(coefs)
    group['COEFS'] = a
    group['LREG'] = model(group[x], a)
    return group

def LinearRegression(group, x, y):
    # objective function
    def model(x, a, b):
        return a * x + b
    coefs, _ = curve_fit(model, group[x], group[y])
#     a = float(coefs)
    group['COEFS'] = repr(coefs)
    group['LREG'] = model(group[x], *coefs)
    return group

def read_robot_data(robot_path):
    """Read and combine data from all CSV files for a robot"""
    data = {}
    
    try:
        # Read estimate.csv (required) - using space delimiter
        estimate_file = robot_path / "estimate.csv"
        if estimate_file.exists():
            data['estimate'] = pd.read_csv(estimate_file, delim_whitespace=True)
            # Now the columns should be properly separated
        else:
            print(f"Warning: No estimate.csv found in {robot_path}")
            return None
            
        # Read extra.csv (optional)
        extra_file = robot_path / "extra.csv"
        if extra_file.exists():
            try:
                extra_df = pd.read_csv(extra_file, delim_whitespace=True)
                if all(col in extra_df.columns for col in ['ID', 'TIME', 'CPU', 'RAM']):
                    data['extra'] = extra_df
            except:
                data['extra'] = None
                
        # Read sc.csv (optional)
        sc_file = robot_path / "sc.csv"
        if sc_file.exists():
            try:
                sc_df = pd.read_csv(sc_file, delim_whitespace=True)
                if all(col in sc_df.columns for col in ['ID', 'TIME', 'MEAN', 'VOTECOUNT']):
                    data['sc'] = sc_df
            except:
                data['sc'] = None
            
        return data
        
    except Exception as e:
        print(f"Error reading data from {robot_path}: {e}")
        return None

def plot_byz_vs_error(experiment_dir="experiment_G1", true_value=0.25):
    """Create plots analyzing Byzantine robots vs estimation error"""
    # Define color scheme at the start
    colors = {
        'individual_runs': '#E6E6E6',  # Light gray
        'mean_line': '#1f77b4',        # Strong blue
        'confidence': '#a6cee3',        # Light blue
        'true_value': '#d62728',        # Red
        'grid': '#CCCCCC',             # Medium gray
        'mean_error': '#2ca02c'        # Green
    }
    
    # Setup paths
    current_dir = Path(os.path.dirname(os.path.abspath(__file__)))
    results_dir = current_dir / "data"
    plot_dir = current_dir / "plots"
    plot_dir.mkdir(exist_ok=True, parents=True)
    
    # Read and process data
    all_data = []
    exp_base = results_dir / experiment_dir
    
    # Process available configurations
    for rob_byz_dir in exp_base.glob("24rob-*byz"):
        byz_count = int(rob_byz_dir.name.split('byz')[0].split('-')[1])
        print(f"\nProcessing configuration: {rob_byz_dir.name}")
        
        # Process available runs (we know we have 9)
        for run in range(1, 10):  # 1-9
            run_path = rob_byz_dir / str(run)
            if not run_path.exists():
                print(f"  Skip: Run {run} not found")
                continue
            
            print(f"  Processing run {run}")
            
            # Process each robot's data
            run_data = []
            for robot in range(1, 25):  # 1-24 (skip 0)
                robot_path = run_path / str(robot)
                if not robot_path.exists():
                    continue
                    
                try:
                    data = read_robot_data(robot_path)
                    if data is None or data.get('estimate') is None:
                        continue
                        
                    # Start with estimate data
                    df = data['estimate'].copy()
                    df['ROBOT_ID'] = robot
                    df['RUN'] = run
                    df['NUM_ROBOTS'] = 24
                    df['NUM_BYZ'] = byz_count
                    
                    # Add performance metrics if available
                    if data.get('extra') is not None:
                        df = df.merge(data['extra'][['TIME', 'CPU', 'RAM']], 
                                    on='TIME', how='left')
                    
                    # Add smart contract data if available
                    if data.get('sc') is not None:
                        df = df.merge(data['sc'][['TIME', 'MEAN', 'VOTECOUNT']], 
                                    on='TIME', how='left')
                    
                    run_data.append(df)
                    
                except Exception as e:
                    print(f"    Error processing robot {robot}: {e}")
            
            if run_data:
                all_data.extend(run_data)
                print(f"    Processed {len(run_data)} robots")
    
    if not all_data:
        print("No data found to plot!")
        return None, None
        
    # Create combined dataframe
    combined_df = pd.concat(all_data, ignore_index=True)
    
    # Print data structure information
    print("\nData Structure:")
    print("Columns:", combined_df.columns.tolist())
    print("\nSample data:")
    print(combined_df.head())
    
    # Print summary of available data
    print("\nData Summary:")
    print(f"Total configurations found: {combined_df['NUM_BYZ'].nunique()}")
    print(f"Runs per configuration: {combined_df['RUN'].nunique()}")
    print(f"Total robots: {combined_df['ROBOT_ID'].nunique()}")
    print(f"Time points per robot: {combined_df.groupby('ROBOT_ID')['TIME'].nunique().mean():.1f} (avg)")
    
    # Calculate absolute error against true value (0.25)
    combined_df['ABS_ERROR'] = abs(combined_df['ESTIMATE'] - true_value)
    combined_df['ERROR'] = combined_df['ESTIMATE'] - true_value
    
    # Create plots
    plt.style.use('seaborn-v0_8')
    
    # 1. Time series plot showing individual runs and mean
    plt.figure(figsize=(15, 8))
    
    # Plot individual runs (thin lines)
    for run in sorted(combined_df['RUN'].unique()):
        run_data = combined_df[combined_df['RUN'] == run].groupby('TIME')['ESTIMATE'].mean()
        plt.plot(run_data.index, run_data.values, 
                alpha=0.3, linewidth=1, 
                color=colors['individual_runs'],
                label='Individual Runs' if run == 1 else None)
    
    # Group by time and calculate statistics
    time_stats = combined_df.groupby('TIME').agg({
        'ESTIMATE': ['mean', 'std', 'count'],
        'ERROR': ['mean', 'std']
    }).reset_index()
    
    plt.axhline(y=true_value, color='r', linestyle='--', label='True Value (25%)')
    
    plt.plot(time_stats['TIME'], 
            time_stats[('ESTIMATE', 'mean')], 
            label='Mean Estimate',
            color='blue',
            linewidth=2)
            
    plt.fill_between(time_stats['TIME'],
                     time_stats[('ESTIMATE', 'mean')] - time_stats[('ESTIMATE', 'std')],
                     time_stats[('ESTIMATE', 'mean')] + time_stats[('ESTIMATE', 'std')],
                     alpha=0.2,
                     color='blue')
    
    plt.xlabel('Time (s)')
    plt.ylabel('White Tile Proportion')
    plt.title('Estimate Evolution Over Time\n(True Value: 25% White Tiles)')
    plt.legend()
    plt.grid(True)
    plt.savefig(plot_dir / 'estimate_over_time.png')
    
    # 2. Box plot of errors by time periods
    plt.figure(figsize=(15, 8))
    
    # Create time periods for analysis
    max_time = combined_df['TIME'].max()
    combined_df['Time Period'] = pd.cut(combined_df['TIME'], 
                                      bins=5,  # 5 equal time periods
                                      labels=['0-20%', '20-40%', '40-60%', '60-80%', '80-100%'])
    
    # Create box plot
    sns.boxplot(x='Time Period', y='ABS_ERROR', 
                data=combined_df, 
                color=colors['mean_line'])
    
    # Add reference line for zero error
    plt.axhline(y=0, 
                color=colors['true_value'], 
                linestyle='--', 
                linewidth=2,
                label='Zero Error')
    
    # Add mean error line
    mean_error = combined_df['ABS_ERROR'].mean()
    plt.axhline(y=mean_error, 
                color=colors['mean_error'], 
                linestyle='-', 
                linewidth=2,
                label=f'Overall Mean Error: {mean_error:.3f}')
    
    plt.xlabel('Experiment Time Period', fontsize=12)
    plt.ylabel('Absolute Error from True Value (25%)', fontsize=12)
    plt.title('Distribution of Estimation Errors Over Time', fontsize=14, pad=20)
    
    # Get current axis limits
    ymin, ymax = plt.ylim()
    plt.ylim(ymin, ymax * 1.2)  # Extend y-axis by 20% to make room for text
    
    # Add text annotations for each period
    for i, period in enumerate(combined_df['Time Period'].unique()):
        period_data = combined_df[combined_df['Time Period'] == period]['ABS_ERROR']
        stats_text = (f'Mean: {period_data.mean():.3f}\n'
                     f'Median: {period_data.median():.3f}\n'
                     f'Std Dev: {period_data.std():.3f}')
        
        # Adjust vertical position for last period
        if i == 4:  # Last period
            plt.text(i, ymax * 0.85, stats_text,  # Lower position for last period
                    horizontalalignment='center',
                    verticalalignment='top',
                    bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
        else:
            plt.text(i, ymax * 1.1, stats_text,
                    horizontalalignment='center',
                    verticalalignment='top',
                    bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
    
    # Move legend to upper right corner, outside the plot
    plt.legend(fontsize=10, 
              framealpha=1, 
              bbox_to_anchor=(1.15, 1),
              loc='upper right')
    
    plt.grid(True, color=colors['grid'], linestyle='-', alpha=0.5)
    
    # Adjust layout to prevent legend cutoff
    plt.tight_layout()
    
    # Save with extra space on right for legend
    plt.savefig(plot_dir / 'error_distribution.png', 
                dpi=300, 
                bbox_inches='tight',
                pad_inches=0.2)
    
    # Print statistical summary
    print("\nStatistical Summary:")
    
    # Calculate convergence metrics
    final_time = combined_df['TIME'].max()
    convergence_window = final_time * 0.1  # Last 10% of time
    converged_data = combined_df[combined_df['TIME'] > (final_time - convergence_window)]
    
    stats = pd.DataFrame({
        'Metric': [
            'True Value',
            'Mean Estimate',
            'Std Estimate',
            'Mean Absolute Error',
            'Std Absolute Error',
            'Mean Bias (Est - True)',
            'Final Mean Estimate',
            'Final Std Estimate',
            'Final Mean Error',
            'Convergence Time',
            'Number of Robots',
            'Number of Runs',
            'Time Points per Robot'
        ],
        'Value': [
            f"{true_value:.3f} (25% white)",
            f"{combined_df['ESTIMATE'].mean():.3f}",
            f"{combined_df['ESTIMATE'].std():.3f}",
            f"{combined_df['ABS_ERROR'].mean():.3f}",
            f"{combined_df['ABS_ERROR'].std():.3f}",
            f"{combined_df['ERROR'].mean():.3f}",
            f"{converged_data['ESTIMATE'].mean():.3f}",
            f"{converged_data['ESTIMATE'].std():.3f}",
            f"{converged_data['ABS_ERROR'].mean():.3f}",
            f"{final_time:.1f}s",
            str(combined_df['NUM_ROBOTS'].iloc[0]),
            str(combined_df['RUN'].nunique()),
            f"{combined_df.groupby('ROBOT_ID')['TIME'].nunique().mean():.1f}"
        ]
    })
    
    print(stats.to_string(index=False))
    
    return combined_df, stats

if __name__ == "__main__":
    df, stats = plot_byz_vs_error()
    plt.show()