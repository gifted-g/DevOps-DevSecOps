use anyhow::Result;
use clap::{Parser, Subcommand};

mod models;
mod storage;

use models::Task;
use storage::Storage;

#[derive(Parser)]
#[command(name = "todo")]
#[command(about = "A simple TODO application", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Add a new task
    Add {
        /// The title of the task
        #[arg(required = true)]
        title: String,
    },
    /// List all tasks
    List,
    /// Complete a task
    Complete {
        /// The ID of the task to complete
        #[arg(required = true)]
        id: usize,
    },
    /// Delete a task
    Delete {
        /// The ID of the task to delete
        #[arg(required = true)]
        id: usize,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut storage = Storage::new("data/tasks.json")?;

    match cli.command {
        Commands::Add { title } => {
            let task = Task::new(title);
            storage.add_task(task)?;
            println!("Task added successfully!");
        }
        Commands::List => {
            let tasks = storage.get_tasks()?;
            if tasks.is_empty() {
                println!("No tasks found.");
                return Ok(());
            }

            println!("Tasks:");
            for (idx, task) in tasks.iter().enumerate() {
                let status = if task.completed { "[x]" } else { "[ ]" };
                println!(
                    "{}. {} {} (Created: {})",
                    idx + 1,
                    status,
                    task.title,
                    task.created_at
                );
            }
        }
        Commands::Complete { id } => {
            if storage.complete_task(id - 1)? {
                println!("Task marked as completed!");
            } else {
                println!("Task not found!");
            }
        }
        Commands::Delete { id } => {
            if storage.delete_task(id - 1)? {
                println!("Task deleted successfully!");
            } else {
                println!("Task not found!");
            }
        }
    }

    Ok(())
}