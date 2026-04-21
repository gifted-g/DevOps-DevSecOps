use crate::models::Task;
use anyhow::{Context, Result};
use std::fs::{self, File};
use std::io::BufReader;
use std::path::Path;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum StorageError {
    #[error("Failed to read tasks file: {0}")]
    ReadError(#[from] std::io::Error),

    #[error("Failed to parse tasks file: {0}")]
    ParseError(#[from] serde_json::Error),

    #[error("Task with ID {0} not found")]
    TaskNotFound(usize),
}

pub struct Storage {
    file_path: String,
    tasks: Vec<Task>,
}

impl Storage {
    pub fn new(file_path: &str) -> Result<Self> {
        // Ensure the data directory exists
        if let Some(parent) = Path::new(file_path).parent() {
            fs::create_dir_all(parent)?;
        }

        let tasks = if Path::new(file_path).exists() {
            let file = File::open(file_path)
                .with_context(|| format!("Failed to open tasks file: {file_path}"))?;
            let reader = BufReader::new(file);
            serde_json::from_reader(reader)
                .with_context(|| format!("Failed to parse tasks from file: {file_path}"))?
        } else {
            Vec::new()
        };

        Ok(Self {
            file_path: file_path.to_string(),
            tasks,
        })
    }

    pub fn get_tasks(&self) -> Result<Vec<Task>> {
        Ok(self.tasks.clone())
    }

    pub fn add_task(&mut self, task: Task) -> Result<()> {
        self.tasks.push(task);
        self.save()
    }

    pub fn complete_task(&mut self, id: usize) -> Result<bool> {
        if let Some(task) = self.tasks.get_mut(id) {
            task.completed = true;
            self.save()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub fn delete_task(&mut self, id: usize) -> Result<bool> {
        if id < self.tasks.len() {
            self.tasks.remove(id);
            self.save()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    fn save(&self) -> Result<()> {
        let json = serde_json::to_string_pretty(&self.tasks)?;
        fs::write(&self.file_path, json)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_storage_operations() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test_tasks.json");
        let file_path_str = file_path.to_str().unwrap();

        // Create new storage
        let mut storage = Storage::new(file_path_str).unwrap();

        // Add a task
        let task = Task::new("Test task".to_string());
        storage.add_task(task.clone()).unwrap();

        // Get tasks
        let tasks = storage.get_tasks().unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].title, "Test task");

        // Complete task
        assert!(storage.complete_task(0).unwrap());
        let tasks = storage.get_tasks().unwrap();
        assert!(tasks[0].completed);

        // Delete task
        assert!(storage.delete_task(0).unwrap());
        let tasks = storage.get_tasks().unwrap();
        assert!(tasks.is_empty());
    }
}