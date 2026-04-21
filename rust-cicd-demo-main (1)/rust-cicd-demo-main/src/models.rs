use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Task {
    pub title: String,
    pub completed: bool,
    pub created_at: DateTime<Utc>,
}

impl Task {
    pub fn new(title: String) -> Self {
        Self {
            title,
            completed: false,
            created_at: Utc::now(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_task() {
        let title = "Test task".to_string();
        let task = Task::new(title.clone());

        assert_eq!(task.title, title);
        assert!(!task.completed);
        assert!(task.created_at <= Utc::now());
    }
}